{ lib }:

with lib;

rec {
  static = import ../nixos/platform/static.nix { inherit lib; };
  vlans = static.config.flyingcircus.static.vlanIds;

  testkey = {
    priv = ''
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
      QyNTUxOQAAACDEL3cs6kZncaVSHZ+DvTMkiohC3j7MP3ad7Jh40Js6twAAAJjFq84bxavO
      GwAAAAtzc2gtZWQyNTUxOQAAACDEL3cs6kZncaVSHZ+DvTMkiohC3j7MP3ad7Jh40Js6tw
      AAAEDbcHXRiL0+aMh1TaEhnXKqjVpOru/jyfW1Zb6ENAGOcsQvdyzqRmdxpVIdn4O9MySK
      iELePsw/dp3smHjQmzq3AAAAEG1hY2llakBta2ctcmF6ZXIBAgMEBQ==
      -----END OPENSSH PRIVATE KEY-----
    '';
    pub = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMQvdyzqRmdxpVIdn4O9MySKiELePsw/dp3smHjQmzq3 testkey@localhost
    '';
  };

  derivePasswordForHost = prefix:
    builtins.hashString "sha256" (lib.concatStringsSep "/" [
      prefix
      ""
      "machine"
    ]);

    # Returns Sensu check command by name.
    # Newlines in the command are removed to avoid breaking the test script.
    sensuCheckCmd = machine: checkName:
      lib.replaceStrings
        ["\\" "\n"]
        ["" " "]
        machine.config.flyingcircus.services.sensu-client.checks.${checkName}.command;

  /*
    Get a basic configuration for a virtual machine

    Parameters:

      id
        Number of the test node in alphabetic ordered, starting from 1.

        Example: IDs for the following servers would be assigned:

        annetta=1, berta=2, claus=3

        You can also look at the suffix of eth1' MAC using
        server.execute("ip a >&2") to get the ID)

      net.(sto|stb|fe)

        Boolean flag to enable/disable this particular interface. Default fe/srv=true, rest false

      resource_group

        String flag to set resource_group.

      location

        String flag to set location.

      secrets

        Attrset to provide extra secrets.

    Example usage:
      {
        imports = [
          (testlib.fcConfig {
            id = 1;
            net.fe = false; net.stb = true;
            secrets."test" = "test";
          })
        ]
      }

  */

  fcConfig = {
    id ? 1,
    net ? {},
    resource_group ? "test", location ? "test", secrets ? {},
  }: { config, ... }:
  {
    imports = [
      ../nixos
      ../nixos/roles
    ];

    config = {
      virtualisation.vlans = map (vlan: vlans.${vlan}) (attrNames config.flyingcircus.enc.parameters.interfaces);

      flyingcircus.enc.parameters = {
        inherit resource_group location secrets;

        interfaces = mapAttrs (name: vid: {
          mac = "52:54:00:12:0${toString vid}:0${toString id}";
          bridged = false;
          networks = {
            "192.168.${toString vid}.0/24" = [ "192.168.${toString vid}.${toString id}" ];
            "2001:db8:${toString vid}::/64" = [ "2001:db8:${toString vid}::${toString id}" ];
          };
          gateways = {};
        })
          (filterAttrs (name: vid: (!(net ? ${name}) && (name == "srv" || name == "fe")) || net ? ${name} && net.${name}) vlans);
      };
    };
  };

  fcIPMap = listToAttrs (concatLists (mapAttrsToList (name: vid: [
    (nameValuePair "${name}4" {
      quote = false;
      prefix = "192.168.${toString vid}.";
    })
    (nameValuePair "${name}6" {
      quote = true;
      prefix = "2001:db8:${toString vid}::";
    })
  ]) vlans));

  /*
    Get IP from server id
    Examples:
      fcIP.srv6 1 -> "2001:db8:3::1"
      fcIP.quote.srv6 -> "[2001:db8:3::1]"
  */
  fcIP =
    (mapAttrs (type: typeconf: (
      id: "${typeconf.prefix}${toString id}"
    )) fcIPMap) // {
      quote = mapAttrs (type: typeconf:
        id:
          if typeconf.quote then "[${typeconf.prefix}${toString id}]"
          else "${typeconf.prefix}${toString id}"
      ) fcIPMap;
    };

}
