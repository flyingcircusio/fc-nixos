{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with lib;

let
  cfg = config.flyingcircus;

  isStaging = !(attrByPath [ "parameters" "production" ] true cfg.enc);

  collectCmd = if cfg.agent.collect-garbage
    then "nix-collect-garbage --delete-older-than 3d --max-freed 104857600"
    else "echo 'flyingcircus.agent.collect-garbage disabled'";

  humanGid = toString config.ids.gids.users;
  serviceGid = toString config.ids.gids.service;
  log = "/var/log/fc-collect-garbage.log";

  script = ''
    sleep $[ $RANDOM % 30 ]
    started=$(date +%s)
    failed=0
    while read user home; do
      if [[ $home == /var/empty ]]; then
        continue
      fi
      sudo -u $user -H -- \
        fc-userscan -v -S -s 2 -c $home/.cache/fc-userscan.cache -L 10000000 \
        -z '*.egg' -E ${./userscan.exclude} \
        $home || failed=1
    done < <(getent passwd | awk -F: '$4 == ${humanGid} || $4 == ${serviceGid} \
              { print $1 " " $6 }')

    if (( failed )); then
      echo "ERROR: fc-userscan failed"
      exit 1
    else
      ${collectCmd}
    fi
    stopped=$(date +%s)
    echo "$(date -R) time=$((stopped - started))s" >> ${log}
  '';

in {
  options = {
    flyingcircus.agent = {
      collect-garbage =
        mkEnableOption
        "automatic scanning for Nix store references and garbage collection";
    };
  };

  config = mkMerge [
    {
      systemd.tmpfiles.rules = [
        "f ${log}"
      ];
    }

    (mkIf cfg.agent.collect-garbage {

      flyingcircus.services.sensu-client.checks.fc-collect-garbage = {
        notification = "nix-collect-garbage stamp recent";
        command = ''
          ${pkgs.nagiosPluginsOfficial}/bin/check_file_age \
            -f ${log} -w 216000 -c 432000
        '';
      };

      services.logrotate.config = ''
        ${log} {
          monthly
          rotate 6
        }
      '';

      flyingcircus.telegraf.inputs = {
        logparser = [ {
          files = [ "/var/log/fc-collect-garbage.log" ];
          grok = {
            patterns = [
              "%{DATESTAMP_RFC2822:timestamp} time=%{DURATION:time:duration}"
            ];
            measurement = "fc_collect_garbage";
          };
        } ];
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig.Type = "oneshot";
        path = with pkgs; [ fc.userscan gawk nix glibc sudo ];
        environment = { LANG = "en_US.utf8"; };
        inherit script;
      };

      systemd.timers.fc-collect-garbage = {
        description = "Timer for fc-collect-garbage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnStartupSec = "49m";
          OnUnitInactiveSec = "1d";
          RandomizedDelaySec = "1h";
        };
      };

    })
  ];
}
