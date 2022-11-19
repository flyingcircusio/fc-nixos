{ config, pkgs, lib, ... }:

let
  cfg = config.flyingcircus.slurm;
  inherit (config) fclib;
  roleEnabled = config.flyingcircus.roles.slurm-node.enable || config.flyingcircus.roles.slurm-master.enable;

  controlMachine = "slurmtest10";
  nodes = [ "slurmtest10" "slurmtest11" "slurmtest12" ];
  nodeStr = lib.concatStringsSep "," nodes;
  memory = 1983;
  cores = 2;

in
{

  options = with lib; {

    flyingcircus.slurm = {

    };

    flyingcircus.roles = {
      slurm-node = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };

      slurm-master = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };
    };
  };

  config = lib.mkIf roleEnabled {

    services.slurm = {
      inherit controlMachine;
      client.enable = true;
      server.enable = config.flyingcircus.roles.slurm-master.enable;
      nodeName = [ "${nodeStr} CPUs=${toString cores} RealMemory=${toString memory} State=UNKNOWN" ];
      partitionName = [ "processing Nodes=${nodeStr} Default=YES MaxTime=INFINITE State=UP" ];
      extraConfig = ''
        SelectType = select/cons_res
        SelectTypeParameters = CR_CPU_Memory
      '';
    };

    systemd.services.slurmctld = {
      after = [ "network-online.target" ];
    };

    systemd.tmpfiles.rules = [
      "f /etc/munge/munge.key 0400 munge munge - chMrKFAcXMtZACNZUq6A11dIvWn6BJaL"
    ];

    services.munge.password = "/etc/munge/munge.key";

    # XXX: tmpfs???

  };
}
