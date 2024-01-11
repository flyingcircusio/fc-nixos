{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  localCfgDir = cfg.localConfigPath + "/firewall";

  localRules =
    let
      suf = lib.hasSuffix;
    in
    lib.optionalString (pathExists localCfgDir)
      (filterSource
        (p: t: t != "directory" && !(suf "~" p) && !(suf "/README" p))
        localCfgDir);

  filteredRules =
    pkgs.runCommand "firewall-local-rules" { inherit localRules; }
    ''
      if [[ -d $localRules ]]; then
        ${pkgs.python3.interpreter} ${./filter-rules.py} $localRules/* > $out
      else
        touch $out
      fi
    '';

  rgAddrs = map (e: e.ip) cfg.encAddresses;
  rgRules = lib.optionalString
    (lib.hasAttr "ethsrv" config.networking.interfaces)
    (lib.concatMapStringsSep "\n"
      (a:
        "${fclib.iptables a} -A fc-resource-group " +
        "-s ${fclib.stripNetmask a} -j nixos-fw-accept")
      rgAddrs);

  checkIPTables = with pkgs; writeScript "check-iptables" ''
    #! ${runtimeShell} -e
    PATH=${lib.makeBinPath [ iptables gnugrep ]}:$PATH
    check=CHECK_IPTABLES
    for cmd in iptables ip6tables; do
      if ! $cmd -L INPUT -n | egrep -q '^nixos-fw'; then
        echo "$check CRITICAL - chain nixos-fw not active in $cmd"
        exit 2
      fi
    done
    echo "$check OK - chain nixos-fw active"
    exit 0
  '';

in
{
  config = {

    environment.etc."local/firewall/README".text = ''
      Add local firewall rules in configuration file snippets. Firewall rules
      should generally be added to the 'nixos-fw' chain. Use jump targets
      'nixos-fw-accept' and 'nixos-fw-log-refuse'/'nixos-fw-refuse' for improved
      packet counting. Standard targets like ACCEPT and REJECT are ok, too.

      Each snippet should only contain iptables/ip6tables/ip46tables commands,
      one per line. Don't put anything else in or the configuration will be
      refused. Host names instead of IP addresses are allowed but generally not
      recommended.

      Activating the rules listed here by calling `fc-manage`.

      Standard chains:

      - nixos-fw: normal accept/reject rules
      - nixos-nat-pre: prerouting rules, e.g. port redirects (-t nat)
      - nixos-nat-post: postrouting rules, e.g. masquerading (-t nat)

      See also https://doc.flyingcircus.io/roles/fc-23.11-production/firewall.html
    '';

    flyingcircus.services.sensu-client.checks = {
      firewall-config = {
        notification = "Firewall configuration did not terminate successfully";
        command = ''
          check_file_age -i -c10 -f /var/lib/firewall/configuration-in-progress
        '';
      };

      firewall-active = {
        notification = "Firewall rules not properly activated";
        command = "/run/wrappers/bin/sudo ${checkIPTables}";
      };
    };

    # This is just to create nixos-nat-(pre|post) ruleset. No further
    # configuration on the NixOS side. Users may set additional networking.nat.*
    # options in /etc/local/nixos.
    networking.nat.enable = true;
    networking.nat.externalInterface = fclib.network.fe.device;

    networking.firewall =
      # our code generally assumes IPv6
      assert config.networking.enableIPv6;
      {
        allowPing = true;
        checkReversePath = "loose";
        rejectPackets = true;

        extraCommands =
        lib.mkMerge [
          (lib.mkOrder 1100 ''
            # FC firewall rules (1100)
            # Accept traffic within the same resource group.
            ip46tables -N fc-resource-group
            ${rgRules}
            ip46tables -A nixos-fw -i ethsrv -j fc-resource-group
            # End FC firewall rules (1100)
          '')

          (lib.mkAfter ''
            # Local firewall rules (after).
            # This option instructs bash to print shell input lines as they are read.
            set -v
            ${readFile filteredRules}
            # End local firewall rules (after)
          '')
        ];

        extraStopCommands = lib.mkOrder 1200 ''
          # FC firewall rules (1200)
          ip46tables -D nixos-fw -i ethsrv -j fc-resource-group 2>/dev/null || true
          ip46tables -F fc-resource-group 2>/dev/null || true
          ip46tables -X fc-resource-group 2>/dev/null || true
          # End FC firewall rules (1200)
        '';

      };

    flyingcircus.passwordlessSudoPackages =
      let ipt = x: "bin/ip${x}tables";
      in [
        {
          commands = [ "${ipt ""} -L*"
                       "${ipt "6"} -L*" ];
          package = pkgs.iptables;
          groups = [ "users" "service" ];
        }
      ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${checkIPTables}" ];
        groups = [ "sensuclient" ];
      }
    ];

    flyingcircus.localConfigDirs.firewall = {
      dir = toString localCfgDir;
    };

  };
}
