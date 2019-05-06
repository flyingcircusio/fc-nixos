# TODO: test - need to port box server first
{ lib, config, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  boxServer = lib.findFirst (s: s.service == "box-server") {} cfg.encServices;
  boxMount = "/mnt/auto/box";
  nfsOpts = [
    "rw" "soft" "intr" "rsize=8192" "wsize=8192" "noauto" "x-systemd.automount"
  ];

in {
  options.flyingcircus = {
    box.enable = lib.mkEnableOption "Flying Circus NFS box client";
  };

  config =
    lib.mkIf (cfg.box.enable && boxServer ? address) (
      let
        humans = filter
          (u: u.class == "human" && u ? "home_directory")
          cfg.users.userData;
        userHomes = listToAttrs
          (map (u: lib.nameValuePair u.uid u.home_directory) humans);
      in
      {
        environment.systemPackages = [ pkgs.fc.box ];
        security.wrappers.box.source = "${pkgs.fc.box}/bin/box";

        fileSystems = lib.listToAttrs
          (map
            (user: lib.nameValuePair
              "${boxMount}/${user}"
              {
                device = "${boxServer.address}:/srv/nfs/box/${user}";
                fsType = "nfs4";
                options = nfsOpts;
                noCheck = true;
              })
            (attrNames userHomes));

        systemd.tmpfiles.rules =
          [ "d ${boxMount}" ] ++
          lib.mapAttrsToList
            (user: home: "L ${home}/box - - - - ${boxMount}/${user}")
            userHomes;
      });
}
