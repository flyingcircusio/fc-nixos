{ lib }:
with lib;
rec {

  # get the DN of this node for LDAP logins.
  getLdapNodeDN = config:
    "cn=${config.networking.hostName},ou=Nodes,dc=gocept,dc=com";

  # Compute LDAP password for this node.
  getLdapNodePassword = config:
    builtins.hashString "sha256" (concatStringsSep "/" [
      "ldap"
      config.flyingcircus.enc.parameters.directory_password
      config.networking.hostName
    ]);

  mkPlatform = lib.mkOverride 900;

}
