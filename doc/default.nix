{ pkgs ? import <nixpkgs> {}
, branch ? "20.09"
, updated ? "2020-12-03 10:18:00"
}:

let
  buildEnv = pkgs.python3.withPackages (ps: [ ps.sphinx ps.sphinx_rtd_theme ]);

in pkgs.stdenv.mkDerivation rec {
  name = "platform-doc-${version}";
  version = "${branch}-${builtins.substring 0 10 updated}";
  src = pkgs.lib.cleanSource ./.;

  patchPhase = ''
    substituteInPlace src/index.rst --subst-var branch
    substituteInPlace src/conf.py --subst-var branch \
                                  --subst-var version \
                                  --subst-var updated
  '';
  inherit branch updated;

  configurePhase = ":";
  buildInputs = [ buildEnv ] ++ (with pkgs; [ python3 git ]);
  buildPhase = "sphinx-build -j 10 -a -b html src $out";

  installPhase = ":";
  doCheck = false;
  dontFixup = true;
}
