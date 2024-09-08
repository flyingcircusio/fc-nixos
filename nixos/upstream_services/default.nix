# Modules taken from upstream NixOS.
# Can be from the same or different NixOS versions.
{ lib, ... }:
let
  modulesFromHere = [
  ];

in {
  disabledModules = modulesFromHere;

  imports = with lib; [
  ];
}
