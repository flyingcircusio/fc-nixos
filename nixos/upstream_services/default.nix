# Modules taken from upstream NixOS.
# Can be from the same or different NixOS versions.
{ lib, ... }:
let
  modulesFromHere = [
    "services/search/opensearch.nix"
  ];

in {
  disabledModules = modulesFromHere;

  imports = with lib; [
    # from nixos-23.05
    ./opensearch
  ];
}
