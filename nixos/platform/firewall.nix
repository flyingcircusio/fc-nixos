{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  # Technically, snippets in /etc/local/firewall are plain shell scripts. We
  # don't want to support full (root) shell expressiveness here, so restrict
  # commands to iptables and friends and quote all shell special chars.
  filterRules =
    pkgs.writeScript "filter-firewall-local-rules.py" ''
      #!${pkgs.python3.interpreter}
      import fileinput
      import re
      import shlex
      import sys
      import os.path as p
      R_ALLOWED = re.compile(r'^(#.*|ip(6|46)?tables .*)?''$')

      for line in fileinput.input():
        atoms = (shlex.quote(s) for s in shlex.split(line.strip(), comments=True))
        m = R_ALLOWED.match(' '.join(atoms))
        if m:
          if m.group(1):
            print(m.group(1))
        else:
          fn = fileinput.filename()
          print('ERROR: only iptables statements or comments allowed:'
                '\n{}\n(included from ${cfg.firewall.localDir}/{})'.\
                format(line.strip(), p.basename(fn)),
                file=sys.stderr)
          sys.exit(1)
    '';

  localRules =
    let
      suf = lib.hasSuffix;
    in
    lib.optionalString (pathExists cfg.firewall.localDir)
      (filterSource
        (p: t: t != "directory" && !(suf "~" p) && !(suf "/README" p))
        cfg.firewall.localDir);

  filteredRules =
    pkgs.runCommand "firewall-local-rules" { inherit localRules; }
    ''
      if [[ -d $localRules ]]; then
        ${filterRules} $localRules/* > $out
      else
        touch $out
      fi
    '';

  rgAddrs = map (e: e.ip) cfg.encAddresses;
  rgRules = lib.optionalString
    (lib.hasAttr "ethsrv" config.networking.interfaces)
    (lib.concatMapStringsSep "\n"
      (a:
        "${fclib.iptables a} -A nixos-fw -i ethsrv " +
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
  options = {
    flyingcircus.firewall.localDir = lib.mkOption {
      type = lib.types.path;
      default = "/etc/local/firewall";
      description = "Directory containing firewall configuration snippets.";
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


      Examples
      --------

      Accept TCP traffic from ethfe to port 32542:

      ip46tables -A nixos-fw -p tcp -i ethfe --dport 32542 -j nixos-fw-accept


      Reject traffic from certain networks in separate chain:

      ip46tables -N blackhole
      iptables -A blackhole -s 192.0.2.0/24 -j DROP
      ip6tables -A blackhole -s 2001:db8::/32 -j DROP
      ip46tables -A nixos-fw -j blackhole
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
        command = "sudo ${checkIPTables}";
      };
    };

    networking.firewall =
      # our code generally assumes IPv6
      assert config.networking.enableIPv6;
      {
        allowPing = true;
        checkReversePath = "loose";
        rejectPackets = true;

        extraCommands =
          let
            rg = lib.optionalString
              (rgRules != "")
              "# Accept traffic within the same resource group.\n${rgRules}\n\n";
            local = "# Local firewall rules.\n${readFile filteredRules}\n";
          in rg + local;
      };

    security.sudo.extraRules =
      let ipt = x: "${pkgs.iptables}/bin/ip${x}tables";
      in [
        {
          commands = [ "${ipt ""} -L*" "${ipt "6"} -L*" ];
          groups = [ "users" "service" ];
        }
        {
          commands = [ "${checkIPTables}" ];
          users = [ "sensuclient" ];
        }
      ];

    system.activationScripts.local-firewall =
      lib.stringAfter [ "users" "groups" ] ''
        install -d -o root -g service -m 02775 ${cfg.firewall.localDir}
      '';

  };
}
