{ pkgs ? import <nixpkgs> { }
, stdenv ? pkgs.stdenv
, mkDerivation ? stdenv.mkDerivation
, makeWrapper ? pkgs.makeWrapper
, php ? pkgs.php
, lib ? pkgs.lib
, ...
}:
let
  src = builtins.fetchTarball {
    url = "https://downloads.fcio.net/nixos-support/testPcre.tgz";
    sha256 = "1klibmqvkyx037zmvjazjq7qlg6rwb8cc9zs2zqsnq05zrf4614d";
  };
in
mkDerivation {
  inherit src;
  name = "testPcre";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out
    cp -r $src/* $out

    substituteInPlace $out/vendor/typo3fluid/fluid/bin/fluid \
      --replace '/usr/bin/env php' '${php}/bin/php'

    patchShebangs $out/vendor/typo3fluid/fluid/bin

    # --chdir "$out" \ on newer vrsions
    wrapProgram $out/testPcre.sh \
      --run "cd \"$out\"" \
      --prefix PATH : "${lib.makeBinPath [ php ]}"
  '';
}
