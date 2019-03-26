{ pkgs, lib, stdenv, python3, patchelf, binutils, makeWrapper }:

stdenv.mkDerivation rec {
  name = "fix-so-rpath";
  src = ./fix-so-rpath.py;
  unpackPhase = ":";
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 patchelf binutils ];
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  installPhase = ''
    install -D -m 755 $src $out/bin/.fix-so-rpath.py
    makeWrapper $out/bin/.fix-so-rpath.py $out/bin/fix-so-rpath \
      --prefix PATH : ${lib.makeBinPath propagatedBuildInputs}
  '';
  meta = with lib; {
    description = ''
      Find .so files without rpath header and fill in ~/.nix-profile/lib
    '';
    maintainer = [ maintainers.ckauhaus ];
    license = [ licenses.bsd3 ];
  };
}
