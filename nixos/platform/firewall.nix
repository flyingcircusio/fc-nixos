{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus;
  cfgUpstream = config.networking.firewall;

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
  rgRules = let
    srv_interface = fclib.network.srv.interface or "";
    in lib.optionalString
    (lib.hasAttr srv_interface config.networking.interfaces)
    (lib.concatMapStringsSep "\n"
      (a:
        "${fclib.iptables a} -A nixos-fw -i ${srv_interface} " +
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
  options.flyingcircus.firewall = {
    logRateLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "10/second";
      description = "average rate limit to use for logging refused IPtables matches,"
        + " see `--limit` in `man 8 iptables-extensions`.\n"
        "Disabled when `null`.";
    };
    logBurstLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "burst limit to use for logging refused IPtables matches,"
        + " see `--limit-burst` in `man 8 iptables-extensions`.\n"
        "Only enabled when `logRateLimit` is enabled.";
    };
    logLevel = lib.mkOption {
      type = lib.types.ints.positive;
      # note for upstreaming: defaults to 6 (info) in NixOS
      default = 7;
      description = ''
        Logging priority for `nixos-fw-log-refuse` messages. Possible values:
        0 (emerg), 1 (alert), 2 (crit), 3 (error), 4 (warning), 5 (notice), 6 (info), 7 (debug)
      '';
    };
    enableSrvRgFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only accept connections from hosts in the same resource "
        + "group on the SRV interface.";
    };
  };
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

      See also https://doc.flyingcircus.io/roles/fc-21.05-production/firewall.html
    '';

    environment.systemPackages = [ pkgs.conntrack-tools ];

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
    networking.nat.externalInterface = fclib.mkPlatform fclib.network.fe.interface;

    networking.firewall =
      # our code generally assumes IPv6
      assert config.networking.enableIPv6;
      {
        allowPing = true;
        checkReversePath = "loose";
        rejectPackets = true;

        extraCommands = lib.mkMerge [
          # Introduce custom managed chains for raw OUTPUT and raw PREROUTING
          (lib.mkBefore ''
            # FC firewall managed chains (before)
            ip46tables -t raw -N fc-raw-output 2>/dev/null || true
            ip46tables -t raw -A OUTPUT -j fc-raw-output

            ip46tables -t raw -N fc-raw-prerouting 2>/dev/null || true
            ip46tables -t raw -A PREROUTING -j fc-raw-prerouting
            # End FC firewall managed chains (before)
          '')
          # Introduce rate limited logging for refused connections -
          # in contrast to non-rate limited logging defined by upstream.
          #
          # As we flush the full chain defined in upstream NixOS, we need to
          # recreate the parts we'd like to keep. Thus, this is mainly copied
          # over, just modified by adding the option for rate-limiting the
          # LOGs.
          # Flushing and recreating the full chain is deemed more resilient
          # than replacing single rules of a chain.
          (lib.mkOrder 1100 (
            let
              logLimits = lib.optionalString (! isNull cfg.firewall.logRateLimit)
                  "-m limit --limit ${cfg.firewall.logRateLimit} --limit-burst ${toString cfg.firewall.logBurstLimit} ";
            in ''
              ${lib.optionalString cfgUpstream.logRefusedConnections ''
                  ip46tables -A nixos-fw-log-refuse ${logLimits}-p tcp --syn -j LOG --log-level ${toString cfg.firewall.logLevel} --log-prefix "refused connection: "
              ''}
              ${lib.optionalString (cfgUpstream.logRefusedPackets && !cfgUpstream.logRefusedUnicastsOnly) ''
                ip46tables -A nixos-fw-log-refuse -m pkttype --pkt-type broadcast \
                  ${logLimits}\
                  -j LOG --log-level ${toString cfg.firewall.logLevel} --log-prefix "refused broadcast: "
                ip46tables -A nixos-fw-log-refuse -m pkttype --pkt-type multicast \
                  ${logLimits}\
                  -j LOG --log-level ${toString cfg.firewall.logLevel} --log-prefix "refused broadcast: "
                  -j LOG --log-level ${toString cfg.firewall.logLevel} --log-prefix "refused multicast: "
              ''}
              ip46tables -A nixos-fw-log-refuse -m pkttype ! --pkt-type unicast -j nixos-fw-refuse
              ${lib.optionalString cfgUpstream.logRefusedPackets ''
                ip46tables -A nixos-fw-log-refuse \
                  ${logLimits}\
                  -j LOG --log-level ${toString cfg.firewall.logLevel} --log-prefix "refused packet: "
              ''}
              ip46tables -A nixos-fw-log-refuse -j nixos-fw-refuse
            ''))
            # Same RG SRV rules
          (lib.mkOrder 1200
            (if cfg.firewall.enableSrvRgFirewall
             then (lib.optionalString (rgRules != "")
               "# Accept traffic within the same resource group.\n${rgRules}\n\n")
             else ''
               # Accept traffic on the SRV interface
               ip46tables -A nixos-fw -i ${fclib.network.srv.interface} -p tcp --dport 9126 -j nixos-fw-refuse
               ip46tables -A nixos-fw -i ${fclib.network.srv.interface} -j nixos-fw-accept
             ''
            ))
            # Local firewall rules.
            (lib.mkOrder 1300 (''
              # Local firewall rules.
              set -v
              ${readFile filteredRules}
            ''))
          ];

        extraStopCommands = lib.mkOrder 1300 ''
          # FC firewall managed chains
          ip46tables -t raw -D OUTPUT -j fc-raw-output 2>/dev/null || true
          ip46tables -t raw -F fc-raw-output 2>/dev/null || true
          ip46tables -t raw -X fc-raw-output 2>/dev/null || true

          ip46tables -t raw -D PREROUTING -j fc-raw-prerouting 2>/dev/null || true
          ip46tables -t raw -F fc-raw-prerouting 2>/dev/null || true
          ip46tables -t raw -X fc-raw-prerouting 2>/dev/null || true
          # End firewall managed chains
        '';
      };

    flyingcircus.passwordlessSudoRules =
      let ipt = x: "${pkgs.iptables}/bin/ip${x}tables";
      in [
        {
          commands = [ "${ipt ""} -L*"
                       "${ipt "6"} -L*" ];
          groups = [ "users" "service" ];
        }
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
