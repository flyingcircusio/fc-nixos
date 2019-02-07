{ config }:
# returns the verbatim contents of /etc/nixos/configuration.nix
''
  { lib, ... }:

  with builtins;
  {
    imports = [
      <fc/nixos>
      /etc/nixos/local.nix
    ];

    flyingcircus.infrastructureModule = "${config.flyingcircus.infrastructureModule}";
  }
''
