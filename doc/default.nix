# Builds roles documentation for his specific branch.
#
# Run without arguments to get a local build:
#
# nix-build
#
# A checkout of the general platform docs may be passed to get backreferences
# right, e.g.:
# --arg platformDoc '{ outPath = path/to/doc; gitTag = ""; revCount = ""; shortRev = ""; }'

{
  pkgs ? import <nixpkgs> {}
, branch ? "22.05"
, updated ? "1970-01-01 01:00"
, platformDoc ? null # directory/URL containing platform objects.inv
, failOnWarnings ? false
}:

let
  # Remove vendored myst-docutils when on 22.11
  myst-docutils = pkgs.python3Packages.callPackage ./myst-docutils.nix {};
  buildEnv = pkgs.python3.withPackages (ps: with ps; [
    linkify-it-py
    myst-docutils
    sphinx
    sphinx_rtd_theme
  ]);
  rg = "${pkgs.ripgrep}/bin/rg";

in pkgs.stdenv.mkDerivation rec {
  name = "platform-doc-${version}";
  version = "${branch}-${builtins.substring 0 10 updated}";
  src = pkgs.lib.cleanSource ./.;

  inherit branch updated platformDoc;

  configurePhase = ":";
  buildInputs = [ buildEnv ] ++ (with pkgs; [ python3 git ]);
  buildPhase = "sphinx-build -j 10 -a -b html src $out |& tee -a build.log";

  installPhase = ":";
  doCheck = failOnWarnings;
  checkPhase =
    let
      preprocess = pkgs.writeScript "filter-acceptable-warnings" ''
        #! ${pkgs.stdenv.shell}
        ${rg} -vF 'WARNING: failed to reach any of the inventories'
      '';
    in ''
      if ${rg} --pre ${preprocess} -F 'WARNING: ' build.log; then
        echo "^^^ Warnings mentioned above must be fixed ^^^"
        false
      fi
  '';
  dontFixup = true;
}
