{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  mkConfig = interface:
    pkgs.writeText "pmacctd-${interface}.conf" ''
      interface: ${interface}
      aggregate: src_host,dst_host

      plugins: print

      print_refresh_time: 60
      print_output: csv
      print_output_file: /var/spool/pmacctd/${interface}-%Y%m%d-%H%M-%s.txt
      print_history: 1m
      print_output_file_append: true
    '';

  mkService = interface: lib.nameValuePair "pmacctd-${interface}" {
    description = "Collect traffic accounting data";
    wantedBy = [ "multi-user.target" ];
    requires = [ "network-addresses-${interface}.service" ];
    stopIfChanged = false;
    script = ''
      ${pkgs.pmacct}/bin/pmacctd -f ${mkConfig interface}
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "1s";
    };
  };
in
lib.mkIf role.enable {
  environment.systemPackages = with pkgs; [
    pmacct
  ];

  environment.etc."pmacctd-${fclib.network.fe.interface}".source = mkConfig fclib.network.fe.interface;
  environment.etc."pmacctd-${fclib.network.srv.interface}".source = mkConfig fclib.network.srv.interface;

  systemd.services =
    lib.listToAttrs [
      (mkService fclib.network.fe.interface)
      (mkService fclib.network.srv.interface)
    ];

  systemd.tmpfiles.rules = [
    "d /var/spool/pmacctd 0700 root root 5d"
  ];
}
