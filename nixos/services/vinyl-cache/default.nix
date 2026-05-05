{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  inherit (config) fclib;
  cfg = config.flyingcircus.services.vinyl-cache;
  vcfg = config.services.vinyl-cache;
  vadm = "${vcfg.package}/bin/vinyladm";

  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkPackageOption
    ;

  sanitizeConfigName =
    name: builtins.replaceStrings [ "." ] [ "-" ] (lib.strings.sanitizeDerivationName name);
  mkVclName = file: "vcl_${builtins.head (lib.splitString "." (builtins.baseNameOf file))}";

  mkHostSelection =
    hcfg:
    let
      # enforce a nix-generated filepath here to ensure that it will change with the input
      # otherwise there is no reliable way to tell that we need to reload the file
      includefile = pkgs.writeText "${hcfg.host}.vcl" hcfg.config;

      # Vinyl Cache uses a two-step approach with config names and labels, that we
      # leverage in this way:
      # 1. Every vhost received a config file that is written as a VCL config
      #    in the nix store, so every vhost's config file name changes when
      #    the config changes. We reflect this change in the config name within
      #    Vinyl Cache so that we can load multiple configs for the same vhost
      #    at the same time to facilitate graceful switchover.
      # 2. The label for every vhost stays the same, independent of any changes
      #    in the config. The label is then pointed to a new (versioned) name
      #    from step 1 to perform the switch-over.
      name = mkVclName includefile;
      label = "label-${sanitizeConfigName hcfg.host}";
    in
    {
      # This is the VCL snippet that will be embedded into the main VCL config.
      config = ''
        if (${hcfg.condition}) {
          return(vcl(${label}));
        }
      '';

      # this is a shell snippet that reloads the File if necessary and labels it appropriately
      command = ''
        load ${name} ${includefile}
        label ${label} ${name}
      '';
    };

  mainConfig = pkgs.writeText "main-config" ''
    vcl 4.0;
    import std;

    # An (invalid) backend that will never be used but is needed
    # to created a syntactically valid config.
    backend default {
      .host = "0.0.0.0";
      .port = "80";
    }

    sub vcl_recv {
      ${virtualHostSelection}

      return (synth(503, "Internal Error"));
    }
  '';

  allVirtualHosts = lib.recursiveUpdate config.flyingcircus.services.varnish.virtualHosts cfg.virtualHosts;

  vhosts = map mkHostSelection (
    (builtins.attrValues allVirtualHosts)
    ++ (lib.optionals (cfg.fallbackConfig != "") [
      {
        config = cfg.fallbackConfig;
        host = "localhost";
        condition = "true";
      }
    ])
  );
  virtualHostSelection = (lib.concatStringsSep "else" (builtins.catAttrs "config" vhosts));

  startupscript =
    let
      name = mkVclName mainConfig;
      vhostActivationCommands = lib.concatStringsSep "\n" (builtins.catAttrs "command" vhosts);
    in
    pkgs.writeShellScript "vinyld-commands.sh" ''
      set -e
      vadm="${vadm}"

      # the vcl.load call will fail in either of 2 cases:
      # 1. the name is already taken
      # 2. the file cannot be compiled (e.g. due to syntax errors)
      # the former does not provide useful information since the vcl names include a nix hash
      # that changes with the files contents. if the name doesnt change odds are the file
      # didnt either so we can just ignore it
      # the latter case we are interested in. failing to compile the file should fail during
      # service reloads and let the caller know that it did
      # since both of these cases return an exit code of 1 and parsing the error output is brittle
      # and breaks easily, we resort to checking if the name is already loaded at the time a reload
      # is triggered
      vcls=$($vadm vcl.list | ${pkgs.gawk}/bin/awk '{ print $5; }')
      load() {
        vcl_name=$1
        vcl_file=$2

        for vcl in $vcls; do
            if [[ "$vcl" == "$vcl_name" ]]; then
                return
            fi
        done
        $vadm vcl.load $vcl_name $vcl_file
      }

      # labeling does not throw an error if the label name is already given to the same vcl name so it
      # can be run every time for good measure and doesnt need to be guarded and should be run every time
      label() {
        label_name=$1
        vcl_name=$2
        $vadm vcl.label $label_name $vcl_name
      }

      # activate all vhosts
      ${vhostActivationCommands}

      load ${name} ${mainConfig}

      # just like labelling vcl.use does not error when calling it with an identical vcl name
      # so can/shouuld be run every time
      $vadm vcl.use ${name}
    '';
in
{
  options.flyingcircus.services.vinyl-cache = {
    enable = mkEnableOption "Vinyl-cache Cache";
    package = mkPackageOption pkgs "varnish" { };
    extraCommandLine = mkOption {
      type = types.separatedString " ";
      default = "";
    };
    # cfg.fallbackConfig is defined seperately to ensure proper ordering when assembling the final configuration.
    # Unlike lists dictionaries do not have a defined ordering, which is why the fallback config is defined seperately.
    # This ensures that it comes last in the finished Vinyl-cache Cache configuration - just as the name implies
    fallbackConfig = mkOption {
      type = types.lines;
      description = ''
        This config triggers when no condition of another virtual host is met.
        Its contents are appended to the config file.
      '';
      default = ''
        vcl 4.0;
        import std;

        backend default {
          .host = "0.0.0.0";
          .port = "80";
        }

        sub vcl_recv {
          return (synth(503, "Internal Error"));
        }
      '';
    };
    listen = mkOption {
      type = options.services.vinyl-cache.listen.type;
      description = ''
        Addresses Vinyl Cache should listen on.
        Unix sockets can technically be used for Vinyl Cache, but are not currently supported on the FCIO platform due to monitoring constraints.
      '';
      default = [
        {
          address = "*";
          port = 8008;
        }
      ];
    };
    virtualHosts = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options = {
              host = mkOption {
                type = types.str;
                default = name;
              };

              config = mkOption {
                type = types.lines;
              };

              condition = mkOption {
                type = types.str;
                default = ''req.http.Host == "${config.host}"'';
              };
            };
          }
        )
      );
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.package == config.flyingcircus.roles.webproxy.package && cfg.package == vcfg.package;
        message = "Please modify the Vinyl Cache package with the option `flyingcircus.roles.webproxy.package`.";
      }
    ];
    warnings = lib.optionals (config.flyingcircus.services.varnish.virtualHosts != { }) [
      "Vinyl Cache is still configured using flyingcircus.services.varnish.virtualHosts. Please migrate to flyingcircus.services.vinyl-cache"
    ];
    services.vinyl-cache = {
      inherit (cfg)
        enable
        package
        extraCommandLine
        listen
        ;

      enableConfigCheck = false;
      enableFileLogging = true;
      config = ''
        vcl 4.0;
        import std;

        backend default {
          .host = "0.0.0.0";
          .port = "80";
        }

        sub vcl_recv {
          return (synth(503, "vinyl is starting up"));
        }
      '';
    };

    environment.etc."vinyl-cache/startup.sh".source = startupscript;

    systemd.services.vinyl-cache = {
      postStart = ''
        /etc/vinyl-cache/startup.sh
      '';

      stopIfChanged = false;
      reloadTriggers = [ startupscript ];
      reload = ''
        /etc/vinyl-cache/startup.sh

        coldvcls=$(${vadm} vcl.list | grep " cold " | ${pkgs.gawk}/bin/awk {'print $5'})

        if [ ! -z "$coldvcls" ]; then
          for vcl in "$coldvcls"; do
            ${vadm} vcl.discard $vcl
          done
        fi
      '';

      serviceConfig.RestartSec = lib.mkOverride 90 "10s";
    };
  };
}
