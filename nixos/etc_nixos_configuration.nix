{ config }:
# returns the verbatim contents of /etc/nixos/configuration.nix
''
  {
    imports = [
      <fc/nixos>
      <fc/nixos/roles>
      /etc/nixos/local.nix
    ];

    flyingcircus.infrastructureModule = "${config.flyingcircus.infrastructureModule}";
  }
''
