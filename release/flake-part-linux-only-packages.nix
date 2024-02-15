{ withSystem, ... }:

with builtins;

let
  pkgNamesToCheck = fromJSON (readFile ./important_packages.json);
in
{
  flake = {
    # Packages that only build on Linux.
    packages.x86_64-linux = withSystem "x86_64-linux"
      ({ pkgs, ... }:
        let
          inherit (pkgs) lib;
        in {
            # Evaluating the kernel expression (which we need for finding the version) is only possible on Linux.
            packageVersions = pkgs.writeText "package-versions" (lib.generators.toJSON {}
              (lib.listToAttrs
                (map
                  (name:
                    let p = lib.attrByPath (lib.splitString "." name) null pkgs;
                    in lib.nameValuePair
                    name
                    (if (p != null && (hasAttr "name" p || hasAttr "pname" p))
                      then { pname = lib.getName p; name = p.name or ""; version = (lib.getVersion p); }
                      else {}))
                  pkgNamesToCheck)));
        });
  };
}
