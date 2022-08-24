{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.k3s-nfs;
  export = "/srv/nfs/kubernetes";
  agents = fclib.findServices "k3s-agent-agent";

  exportToClients =
    let
      flags = "rw,sync,no_root_squash,no_subtree_check,anonuid=162,anongid=900";
    in
      lib.concatMapStringsSep " " (a: "${head a.ips}(${flags})") agents;
in
{
  options = with lib; {
    flyingcircus.roles.k3s-nfs = {
      enable = lib.mkEnableOption "Enable K3s (Kubernetes) NFS server (experimental)";
      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {
      services.nfs = {
        server = {
          enable = true;
          exports = ''
            ${export} ${exportToClients}
          '';
        };
      };

      systemd.tmpfiles.rules = [
        "d /srv/nfs/kubernetes 0750 kubernetes service"
      ];

      users.users.kubernetes = {
        uid = config.ids.uids.kubernetes;
        home = "/var/empty";
        group = "kubernetes";
      };
    })

  ];
}
