{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.audit;
in

{
  /* XXX after beta
    imports = [
      (mkRemovedOptionModule [ "flyingcircus" "audit" "enable" ] "Auditing is now enabled by default, this option can be safely removed")
    ];
  */

  options.flyingcircus.audit = {
    enable = mkEnableOption "auditing (beta)";
    useAlloy = mkEnableOption "auditing implementation using grafana alloy and loki";
  };

  config = (mkIf cfg.enable {
    security.audit = {
      enable = true;
      rules = [
        "-a exit,always -F arch=b64 -F euid=0 -S execve"
        "-a exit,always -F arch=b32 -F euid=0 -S execve"
        "-a exit,always -F arch=b64 -F euid=0 -S execveat"
        "-a exit,always -F arch=b32 -F euid=0 -S execveat"
      ];
    };

    security.pam.services = {
      login = {
        setLoginUid = true;
        ttyAudit = {
          enable = true;
          enablePattern = "*";
        };
      };
      sshd = {
        setLoginUid = true;
        ttyAudit = {
          enable = true;
          enablePattern = "*";
        };
      };
      sudo = {
        ttyAudit = {
          enable = true;
          enablePattern = "*";
          openOnly = true;
        };
      };
    };
  });
}
