# Generic stuff that does not fit elsewhere.

{ config, pkgs, lib }:

let
  fclib = config.fclib;

in
with builtins;
with lib;
rec {

  currentRG = with config.flyingcircus;
    if lib.hasAttrByPath [ "parameters" "resource_group" ] enc
    then enc.parameters.resource_group
    else null;

  # Derives a password from host data and a custom prefix
  derivePasswordForHost = prefix:
    builtins.hashString "sha256" (concatStringsSep "/" [
      prefix
      (lib.attrByPath ["parameters" "directory_password"] "" config.flyingcircus.enc)
      config.networking.hostName
    ]);

  getLdapNodePassword = derivePasswordForHost "ldap";

  # get the DN of this node for LDAP logins.
  getLdapNodeDN =
    "cn=${config.networking.hostName},ou=Nodes,dc=gocept,dc=com";

  # Returns service from /etc/nixos/services.json
  # that matches the given name or null, if nothing matches.
  # If there are multiple matches, an error is thrown.
  findOneService = name:
    let
      found = filter (s: s.service == name) config.flyingcircus.encServices;
      len = length found;
    in if len == 0 then null
      else if len == 1 then head found
      else throw ("Multiple matches for service ${name}: "
        + lib.concatMapStringsSep "; " (s: s.address or "<no address>") found);


  # Returns all service clients from /etc/nixos/service_clients.json
  # that match the given name or an empty list, if nothing matches.
  findServiceClients = name:
    filter
      (s: s.service == name)
      config.flyingcircus.encServiceClients;

  # Returns all services from /etc/nixos/services.json
  # that match the given name or an empty list, if nothing matches.
  findServices = name:
    filter
      (s: s.service == name)
      config.flyingcircus.encServices;

  installDirWithPermissions = { user, group, permissions, dir }:
    "install -d -o ${user} -g ${group} -m ${permissions} ${dir}";

  # Allow overrides with default priority (100)
  mkPlatform = lib.mkOverride 900;
  # Allow overrides with default priority (100) but override mkPlatform
  # defaults, i.e. for containers.
  mkPlatformOverride = lib.mkOverride 850;

  mkDisableContainerSupport = lib.mkOption {
    type = lib.types.bool;
    description = "This role is not compatible with (dev) containers.";
    default = false;
  };

  mkEnableContainerSupport = lib.mkOption {
    type = lib.types.bool;
    description = "This role is compatible with (dev) containers.";
    default = true;
  };

  coalesce = list: findFirst (el: el != null) null list;

  servicePassword =
    { file
    , user ? "root"
    , mode ? "0660"
    , token ? ""  # personalize derivation to prevent Nix hash collisions
    }:
    let
      name = builtins.replaceStrings ["/"] ["-"] file;
      generatePasswordCommand =
        "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 -d -c \"${token}\"";
      generatedPassword =
        readFile (
          pkgs.runCommand name { preferLocalBuild = true; }
          "${generatePasswordCommand} > $out");

      # Only install directory if not there, otherwise, permissions might
      # change.
      generatorScript = how: ''
        install -d $(dirname ${file})
        if [[ ! -e ${file} ]]; then
          ( umask 007;
            ${how} > ${file}
            chown ${user}:service ${file}
          )
        fi
        chmod ${mode} ${file}
        '';

    in rec {
      inherit file;

      # Generate in activation, with usable password.value, but with password
      # in nix store.
      activation = generatorScript "echo -n ${generatedPassword}";

      # Generate in preStart of service. password.value is *not* usable, but
      # no password is being stored in nix store.
      generate = generatorScript generatePasswordCommand;

      # Password value for nix configuration. Accessing makes the password
      # to be stored in nix store. A warning is issued.
      value = removeSuffix "\n" (fclib.configFromFile file generatedPassword);
    };

  usersInGroup = group:
    map
      (getAttr "uid")
      (filter
        (u: any (g: g == group) (getAttr currentRG u.permissions))
        config.flyingcircus.users.userData
      );

  writePrettyJSON = name: x:
  let json = pkgs.writeText "write-pretty-json-input" (toJSON x);
  in pkgs.runCommand name { preferLocalBuild = true; } ''
      ${pkgs.jq}/bin/jq . < ${json} > $out
    '';

  python3BinFromFile = path: pkgs.writers.writePython3Bin (removeSuffix ".py" (builtins.baseNameOf path)) {} (lib.readFile path);

}
