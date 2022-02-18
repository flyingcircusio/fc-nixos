{ config, lib, pkgs, ... }:

with builtins;
let
  cfg = config.flyingcircus.roles.devhost;
  fclib = config.fclib;

  testedRoles = attrNames (lib.filterAttrs (n: v: v.supportsContainers or true) config.flyingcircus.roles);
  excludedRoles = attrNames (lib.filterAttrs (n: v: !(v.supportsContainers or true)) config.flyingcircus.roles);


  containersFromDir = dir:
    with lib; 
    (map
      (filename: fromJSON (readFile "${dir}/${filename}"))
      (filter
        (filename: hasSuffix ".json" filename)
        (attrNames (readDirMaybe dir))));

  allContainers = 
    (containersFromDir "/etc/devhost") ++
    (containersFromDir "/etc/devserver");

  enabledContainers = with lib;
    (filter (container: container.enabled or true) allContainers);

  container_script = pkgs.writeShellScriptBin "fc-build-dev-container"
    ''
      #!/bin/sh
      set -ex

      action=''${1?need to specify action}
      container=''${2?need to specify container name}

      manage_alias_proxy=${lib.boolToString cfg.enableAliasProxy}

      case "$action" in
          destroy)
              nixos-container destroy $container || true
              # We can not leave the nginx config in place because this will
              # make nginx stumble over non-resolveable names.
              rm -f /etc/devhost/$container.json
              if [ "$manage_alias_proxy" == true ]; then
                fc-manage -v -b
              fi
              ;;
          ensure)
              channel_url=''${3?need to specify channel url}
              channel_path=''${channel_url#file://}
              aliases=''${4}
              if ! nixos-container status $container; then
                  workdir=$(mktemp -d)
                  cd $workdir
                  echo $workdir
                  cp ${./container-base.nix} configuration.nix
                  cp ${./container-local.nix} local.nix
                  sed -i -e "s/__HOSTNAME__/$container/" local.nix
                  nix-build --option restrict-eval true -I . -I $channel_path -I nixos-config=configuration.nix --no-build-output "<nixpkgs/nixos>" -A system
                  system=$(readlink result)
                  nixos-container create $container --system-path $system
                  nixos-container start $container
                  cp local.nix /var/lib/containers/$container/etc/nixos/local.nix
              else
                  nixos-container start $container
              fi
              mkdir -p /nix/var/nix/profiles/per-container/$container/per-user/root/
              jq -n --arg channel_url "$channel_url" '{parameters: {environment_url: $channel_url, environment: "container"}}' > /var/lib/containers/$container/etc/nixos/enc.json
              # This touches the file and also ensures that we get updates on
              # the aliases if needed.
              container_ip=$(nixos-container show-ip $container)
              jq -n --arg container "$container" \
                --arg aliases "$aliases" \
                --arg ip "$container_ip" \
                '{name: $container, ip: $ip, aliases: ($aliases | split(" ")), enabled: true}' \
                > /etc/devhost/$container.json
              if [ "$manage_alias_proxy" == true ]; then
                fc-manage -v -b
              fi
      esac
    '';
    readDirMaybe = path: if (pathExists path) then readDir path else {};
    clean_script = fclib.python3BinFromFile ./fc-devhost-clean-containers.py;

    makeContainerTestScriptForRole = (role: pkgs.writeShellScript "check_devhost_with_${role}" ''
      #!/bin/sh
      set -euxo pipefail

      record_exit() {
        rv=$?
        directory=/var/tmp/sensu/devhost/${role}
        mkdir -p $directory
        echo $rv > ''${directory}/state
        journalctl _SYSTEMD_INVOCATION_ID=`systemctl show -p InvocationID --value fc-devhost-test-${role}` > ''${directory}/log
        exit 0
      }
      trap record_exit EXIT

      export PATH=/run/wrappers/bin:/root/.nix-profile/bin:/etc/profiles/per-user/root/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin

      container=devhosttest

      fc-build-dev-container destroy $container

      # Avoid duplicate nixexprs.tar.xz but ensure its there.
      url=${cfg.testingChannelURL}
      url=''${url%/nixexprs.tar.xz}/nixexprs.tar.xz
      url=$(curl --head  -Ls -o /dev/null -w %{url_effective} $url)

      fc-build-dev-container ensure $container $url "www"

      cat > /var/lib/containers/$container/etc/local/nixos/container.nix <<__EOF__
      { ... }:
      {
      flyingcircus.roles.${role}.enable = true;
      }
      __EOF__

      nixos-container run $container -- fc-manage -c

      fc-build-dev-container destroy $container
    '');
in

{
  options = {
    flyingcircus.roles.devhost = {

      enable = lib.mkEnableOption "Enable our container-based development host";
      supportsContainers = fclib.mkDisableContainerSupport;

      enableAliasProxy = lib.mkOption {
        description = "Enable HTTPS-Proxy for containers and their aliases.";
        type = lib.types.bool;
        default = !cfg.testing;  # Disable on testing by default.
      };

      publicAddress = lib.mkOption {
        description = "Name of the public address of this development server.";
        type = lib.types.str;
        default = "example.com";
      };

      cleanupContainers = lib.mkOption {
        description = "Whether to automatically shut down and destroy unused containers.";
        type = lib.types.bool;
        default = true;
      };

      testing = lib.mkEnableOption "Enable testing mode that routinely creates and destroys containers and reports status to sensu.";

      testingChannelURL = lib.mkOption {
        description = "URL to an hydra build (see directory) that containers use.";
        type = lib.types.str;
        default = config.flyingcircus.enc.parameters.environment_url;
      };

    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      flyingcircus.roles.webgateway.enable = true;

      environment.systemPackages = [
        container_script
        clean_script
      ];

      security.sudo.extraRules = lib.mkAfter [
          { commands = [ { command = "${container_script}/bin/fc-build-dev-container"; options = [ "NOPASSWD" ]; } ];
            groups = [ "service" "users" ];
          } ];

      systemd.tmpfiles.rules = [
          "d /etc/devhost/"
      ];

      # BBB can be removed after a grace period
      flyingcircus.activationScripts.devhost-migrate-old-config-dir = ''
        if [ -d "/etc/devserver" ]; then
          # Be defensive about whether tmpfiles has already created
          # devhost entry and expect that it might already exist
          # but might not. `mv`ing the directory would break in that
          # case.
          mkdir -p /etc/devhost
          mv /etc/devserver/* /etc/devhost/
          rmdir /etc/devserver
        fi
      '';

      # BBB can be removed after a grace period
      flyingcircus.activationScripts.devhost-migrate-ip-config = ''
        set -x
        cd /etc/devhost
        for filename in *.json; do
          container=''${filename%.json}
          ${pkgs.jq}/bin/jq \
            --arg ip $(${pkgs.nixos-container}/bin/nixos-container show-ip $container) \
            -r '. + {ip:$ip}' "$filename" | ${pkgs.moreutils}/bin/sponge "$filename"
        done
      '';

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        # Increase inotify limits to avoid running out of them when
        # running many containers:
        # https://forum.proxmox.com/threads/failed-to-allocate-directory-watch-too-many-open-files.28700/
        "fs.inotify.max_user_instances" = 512;
        "fs.inotify.max_user_watches" = 16384;
      };
      networking.nat.internalInterfaces = ["ve-+"];

      networking.extraHosts = ''
        # static entries for devhost containers to avoid nginx issues
        # if containers are not running.
        #
        # This could be a problem with duplicate entries, but I think
        # we'll be fine.
      '' + (lib.concatMapStringsSep "\n"
           (container: "${container.ip} ${container.name}")
           (filter (container: container ? ip) allContainers));

      services.nginx.virtualHosts = if cfg.enableAliasProxy then (
        let
          suffix = cfg.publicAddress;
          containers = filter (container: container.aliases != []) enabledContainers;
          generateContainerVhost = container:
          { name = "${container.name}.${suffix}";
            value  = {
              serverAliases = map
                (alias: "${alias}.${container.name}.${suffix}")
                container.aliases;
              forceSSL = true;
              enableACME = true;
              locations."/" = {
                proxyPass = "https://${container.name}";
              };
            };
          };
        in
          builtins.listToAttrs (map generateContainerVhost containers))
        else {};

       systemd.services."container@".serviceConfig = { TimeoutStartSec = lib.mkForce "1min"; };

       # Start containers on system startup, ensure they get started before
       # nginx.

       systemd.services.fc-devhost-start-containers = {
         description = "Start containers on boot.";
         wantedBy = [ "multi-user.target" ];
         wants = [ "network.target" ];
         after = [ "network.target" ];
         before = [ "nginx.service" ] ;
         restartIfChanged = false;
         stopIfChanged = false;

         path = [ pkgs.nixos-container ];
         script = ''
           # Start all enabled containers.

           # be verbose about what you're doing
           set -x

           # Allow individual containers to have problems but start
           # all others. We have to set +e here explicitly as the script
           # will be generated with a #!.../bin/bash -e header
           set +e

         '' + lib.concatMapStringsSep "\n"
           (container: "nixos-container start ${container.name}")
           enabledContainers;

         serviceConfig = {
             Type = "oneshot";
             RemainAfterExit = true;
         };
       };

       # Automated clean up / shut down

       systemd.services.fc-devhost-clean-containers = {
         description = "Clean up old/unused devhost containers.";
         environment = {
           PYTHONUNBUFFERED = "1";
         };
         path = with pkgs; [ clean_script nixos-container ];
         script = "fc-devhost-clean-containers";
         serviceConfig = {
             Type = "oneshot";
             RemainAfterExit = false;
         };
       };

      systemd.timers.fc-devhost-clean-containers = lib.mkIf cfg.cleanupContainers {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00:00";
        };
      };

    })

    (lib.mkIf cfg.testing {

      security.acme.server = "https://acme-staging-v02.api.letsencrypt.org/directory";

      flyingcircus.services.sensu-client.checks = listToAttrs (map (role: {
        name = "devhost_testsuite_${role}";
        value = {
          notification = "DevHost test suite – ${role}";
          command = (let check_command = pkgs.writeShellScript "check" ''
            set -e
            cat /var/tmp/sensu/devhost/${role}/log
            exit $(</var/tmp/sensu/devhost/${role}/state)
          ''; in "${check_command}");
          interval = 10;
        };
      }) testedRoles);

      systemd.timers.fc-devhost-testsuite = {
        description = "Timer for running the devhost test suite";
        requiredBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "15m";
        };
      };

      systemd.services = lib.mkMerge [
      { fc-devhost-testsuite = {
          description = "Run all devhost tests";
          script = ''
            set +e
            cd /etc/systemd/system
            for x in fc-devhost-test-*.service; do
              systemctl start $x;
            done
          '';
          stopIfChanged = false;
          restartIfChanged= false;
          reloadIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
          };
        };
      }

      (listToAttrs (map (role: {
        name = "fc-devhost-test-${role}";
        value = {
          description = "Test devhost container feature for ${role} role";
          # WARNING: path and environment are duplicated from
          # agent.nix. Unfortunately using references causes conflicts
          # that can not be easily resolved.
          path = with pkgs; [
            bzip2
            config.system.build.nixos-rebuild
            fc.agent
            gnutar
            gzip
            utillinux
            xz
          ];
          environment = config.nix.envVars // {
            HOME = "/root";
            LANG = "en_US.utf8";
            NIX_PATH = concatStringsSep ":" config.nix.nixPath;
          };
          script = "${makeContainerTestScriptForRole role}";
          stopIfChanged = false;
          restartIfChanged= false;
          reloadIfChanged = false;
          serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = false;
          };
        };
      }) testedRoles)) ];

      flyingcircus.activationScripts.devhost-test-purge-excluded-roles =
        lib.concatMapStringsSep "\n" (role: "rm -rf /var/tmp/sensu/devhost/${role}") excludedRoles;

    })
  ];

}
