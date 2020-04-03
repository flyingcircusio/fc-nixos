{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with lib;

let
  cfg = config.flyingcircus;
  log = "/var/log/fc-collect-garbage.log";

  garbagecollect = pkgs.writeScript "fc-collect-garbage.py" ''
    #! ${pkgs.python3.interpreter}

    import datetime
    import os
    import pwd
    import subprocess
    import sys

    EXCLUDE="${./userscan.exclude}"

    def main():
        rc = []
        for user in pwd.getpwall():
            if user.pw_uid < 1000 or user.pw_dir == '/var/empty':
                continue
            print(f'Scanning {user.pw_dir} as {user.pw_name}')
            p = subprocess.Popen([
                    "ionice", "-c3", "fc-userscan", "-r", "-c",
                    user.pw_dir + "/.cache/fc-userscan.cache", "-L10000000",
                    "--unzip=*.egg", "-E", EXCLUDE, user.pw_dir],
                stdin=subprocess.DEVNULL,
                preexec_fn=lambda: os.seteuid(user.pw_uid))
            rc.append(p.wait())

        status = max(rc)
        print('Overall status:', status)
        if status >= 2:
            print('ERROR: fc-userscan had hard errors (see above). Aborting')
            sys.exit(2)
        if status >= 1:
            print('WARNING: fc-userscan had soft errors (see above). Aborting')
            sys.exit(1)
        print('Running nix-collect-garbage')
        rc = subprocess.run([
                "ionice", "-c3", "nix-collect-garbage",
                "--delete-older-than", "3d", "--max-freed", "100M"],
            check=True, stdin=subprocess.DEVNULL).returncode
        print('nix-collect-garbage status:', rc)
        open('${log}', 'w').write(str(datetime.datetime.now()) + '\n')
        sys.exit(rc)


    if __name__ == '__main__':
        main()
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
          ${pkgs.monitoring-plugins}/bin/check_file_age \
            -f ${log} -w 216000 -c 432000
        '';
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig.Type = "oneshot";
        path = with pkgs; [ fc.userscan nix glibc utillinux ];
        environment = { LANG = "en_US.utf8"; };
        script = "${pkgs.python3.interpreter} ${garbagecollect}";
      };

      systemd.timers.fc-collect-garbage = {
        description = "Timer for fc-collect-garbage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "00:00:00";
          RandomizedDelaySec = "24h";
        };
      };

    })
  ];
}
