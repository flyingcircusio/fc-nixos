with builtins;

let
  pkgs = import <fc> {};
  lib = pkgs.lib;
  pkgNamesToCheck = fromJSON (readFile ./important_packages.json);

in pkgs.writeText "versions" (lib.generators.toJSON {}
  (lib.listToAttrs
    (map
      (name:
      let p = lib.attrByPath (lib.splitString "." name) null pkgs;
      in lib.nameValuePair
        name
        (if (p != null && (hasAttr "name" p || hasAttr "pname" p))
        then { pname = lib.getName p; name = p.name or ""; version = (lib.getVersion p); }
        else {}))
      pkgNamesToCheck))
)
