{ pkgs, lib, config, ... }:

let
  fclib = config.fclib;
  cfg = config.flyingcircus.go-audit;
  cfgAudit = config.flyingcircus.audit;

in
{
  options.flyingcircus.go-audit = with lib; {
    package = mkOption {
      type = types.package;
      default = pkgs.go-audit;
      defaultText = "pkgs.go-audit";
      example = "pkgs.go-audit";
      description = "The go-audit package to use.";
    };
  };

  # TODO: remove mkIf after beta
  config = lib.mkIf (cfgAudit.enable && cfgAudit.useAlloy) {
    environment.etc."alloy/go-audit.alloy".text = ''
      loki.source.gelf "go_audit" {
        listen_address = "127.0.0.1:12201"
        forward_to = [loki.process.go_audit.receiver]
      }

      loki.process "go_audit" {
        forward_to = [loki.write.fcio_rg_loki.receiver]

        stage.json {
          expressions = {
            message = "short_message",
          }
        }

        stage.output {
          source = "message"
        }
      }
    '';
    systemd.services.alloy.restartTriggers = [ config.environment.etc."alloy/go-audit.alloy".source ];

    systemd.services.go-audit = let
      configFile = pkgs.writeText "go-audit.yaml" (lib.generators.toJSON {} {
        rules = config.security.audit.rules;
        output.gelf = {
          enabled = true;
          address = "127.0.0.1:12201";
        };
      });
    in {
      description = "go-audit";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      conflicts = [ "auditd.service" ];
      path = [ pkgs.audit ];
      serviceConfig = {
        Restart = "always";
        ExecStart = "${cfg.package}/bin/go-audit -config ${configFile}";
      };
    };
  };
}
