# Builds roles documentation for his specific branch.
#
# Run without arguments to get a local build:
#
# nix-build

{
  pkgs ?
    import (fetchTarball "https://hydra.flyingcircus.io/build/5919876/download/1/nixexprs.tar.xz")
      { },
  branch ? "26.11",
  updated ? "1970-01-01 01:00",
  failOnWarnings ? false,
}:

let
  buildEnv = pkgs.python3.withPackages (
    ps: with ps; [
      linkify-it-py
      myst-parser
      sphinx
      sphinx-copybutton
      sphinx-rtd-theme
      furo
    ]
  );
  rg = "${pkgs.ripgrep}/bin/rg";

in
pkgs.stdenv.mkDerivation rec {
  name = "platform-doc-${version}";
  version = "${branch}-${builtins.substring 0 10 updated}";
  src = pkgs.lib.cleanSource ./.;

  inherit branch updated;

  configurePhase = ":";
  buildInputs = [
    buildEnv
  ]
  ++ (with pkgs; [
    python3
    git
  ]);
  buildPhase = "sphinx-build -j 10 -a -b html src $out |& tee -a build.log";

  installPhase = ":";
  doCheck = failOnWarnings;
  checkPhase = ''
    if ${rg} -F 'WARNING: ' build.log; then
      echo "^^^ Warnings mentioned above must be fixed ^^^"
      false
    fi
  '';
  dontFixup = true;
}
