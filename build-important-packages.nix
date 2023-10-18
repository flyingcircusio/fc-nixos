with builtins;

let
  pkgs = import <fc> {};
  pkgNames = fromJSON (readFile ./important_packages.json);
  inherit (pkgs) lib;
in pkgs.symlinkJoin {
  name = "build-important-packages";
  paths = map (p: lib.attrByPath (lib.splitString "." p) null pkgs) pkgNames;
}
