{
  config,
  pkgs,
  lib,
  ...
}:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;

  mkConfig =
    interface:
    lib.nameValuePair "pmacctd-${interface}" {
      source = pkgs.writeText "pmacctd-${interface}.conf" ''
        pcap_interface: ${interface}
        aggregate: src_host,dst_host

        plugins: print

        print_refresh_time: 60
        print_output: csv
        print_output_file: /var/spool/pmacctd/${interface}-%Y%m%d-%H%M-%s.txt
        print_history: 1m
        print_output_file_append: true
      '';
    };

  mkService =
    interface:
    lib.nameValuePair "pmacctd-${interface}" {
      description = "Collect traffic accounting data";
      wantedBy = [ "multi-user.target" ];
      requires = [ "network-addresses-${interface}.service" ];
      after = [ "network-addresses-${interface}.service" ];
      stopIfChanged = false;
      script = ''
        ${pkgs.pmacct}/bin/pmacctd -f ${(mkConfig interface).value.source}
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = "1s";
      };
    };

  accountIfaces = map (net: fclib.network."${net}".interface) role.trafficAccountingNetworks;
in
lib.mkIf (role.enable && role.enableTrafficAccounting) {
  environment.systemPackages = with pkgs; [
    pmacct
  ];

  environment.etc = lib.listToAttrs (map mkConfig accountIfaces);
  systemd.services = lib.listToAttrs (map mkService accountIfaces);

  systemd.tmpfiles.rules = [
    "d /var/spool/pmacctd 0700 root root 5d"
  ];
}
