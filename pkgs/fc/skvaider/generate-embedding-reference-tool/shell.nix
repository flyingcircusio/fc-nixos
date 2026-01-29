# For some numpy issues in some user environments.
{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  ...
}:
pkgs.mkShell {
  shellHook = ''
    addToSearchPath "LD_LIBRARY_PATH" "${lib.getLib stdenv.cc.cc}/lib"
    addToSearchPath "LD_LIBRARY_PATH" "${lib.getLib pkgs.libz}/lib"
  '';
}
