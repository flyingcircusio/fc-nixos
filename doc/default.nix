# Builds roles documentation for his specific branch.
#
# Run without arguments to get a local build:
#
# nix-build
#
# A checkout of the general platform docs may be passed to get backreferences
# right, e.g.:
# --arg platformDoc '{ outPath = path/to/doc; gitTag = ""; revCount = ""; shortRev = ""; }'

{ branch ? "22.05"
, updated ? "1970-01-01 01:00"
, platformDoc ? null # directory/URL containing platform objects.inv
, failOnWarnings ? false
}:

let
  unstableChannel = "https://releases.nixos.org/nixos/unstable/nixos-22.11pre399062.3a11db5f408/nixexprs.tar.xz";
  pkgs = import (fetchTarball unstableChannel) {};
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
