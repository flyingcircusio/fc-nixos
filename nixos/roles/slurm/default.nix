{ config, pkgs, lib, ... }:

let
  cfg = config.flyingcircus.slurm;
  slurmCfg = config.services.slurm;
  inherit (config) fclib;
  roleEnabled = config.flyingcircus.roles.slurm-node.enable || config.flyingcircus.roles.slurm-controller.enable;

  controlMachine = "slurmtest10";
  nodes = [ "slurmtest10" "slurmtest11" "slurmtest12" ];
  nodeStr = lib.concatStringsSep "," nodes;
  memory = 1983;
  cores = 2;

in
{

  options = with lib; {
    flyingcircus.slurm = {

      partitionName = mkOption {
        type = types.str;
        default = "all";
        description = ''
          Name of the default partition which is automatically generated from all known slurm nodes in the
          resource group. Don't use `default` as partition name, it will fail!
        '';
      };

    };

    flyingcircus.roles = {
      slurm-node = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };

      slurm-controller = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };
    };
  };

  config = lib.mkIf roleEnabled {

    environment.etc.slurmd.source = slurmCfg.etcSlurm;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "slurm-config-dir" "echo ${slurmCfg.etcSlurm}")
      (pkgs.writeShellScriptBin "slurm-show-config" ''
        for x in ${slurmCfg.etcSlurm}/*; do
          echo "''${x}:"
          cat $x
        done
      '')
    ];


    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "ALL" ];
        groups = [ "sudo-srv" ];
        runAs = "slurm";
      }
    ];

    services.slurm = {
      inherit controlMachine;
      client.enable = true;
      server.enable = config.flyingcircus.roles.slurm-controller.enable;
      nodeName = [ "${nodeStr} CPUs=${toString cores} State=UNKNOWN" ];
      partitionName = [ "${cfg.partitionName} Nodes=${nodeStr} Default=YES MaxTime=INFINITE State=UP" ];
      extraConfig = ''
        SelectType = select/cons_res
        SelectTypeParameters = CR_CPU_Memory
      '';
    };

    systemd.services.slurmd = {
      after = [ "munged.service" ];
      serviceConfig = {
        Restart = "always";
      };
    };


    systemd.services.slurmctld = {
      serviceConfig = {
        Restart = "always";
      };
    };

    systemd.tmpfiles.rules = [
      "f /etc/munge/munge.key 0400 munge munge - chMrKFAcXMtZACNZUq6A11dIvWn6BJaL"
    ];

    services.munge.password = "/etc/munge/munge.key";




    # XXX: tmpfs???

  };
}
