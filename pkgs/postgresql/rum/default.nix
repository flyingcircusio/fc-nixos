{ stdenv, fetchFromGitHub, postgresql }:

let
  version = "1.3.1";
in
stdenv.mkDerivation {
  name = "rum-${version}";

  src = fetchFromGitHub {
    rev = "${version}";
    owner = "postgrespro";
    repo = "rum";
    sha256 = "1d19r5mb78h0iapnqv5l59kgfcxlcyrvpk2bnnvj06brwzssghia";
  };

  buildInputs = [ postgresql ];

  makeFlags = [
    "USE_PGXS=1"
  ];

   installPhase =
   ''
     mkdir -p $out/{bin,lib}
     cp ./rum.so $out/lib
     mkdir -p $out/share/extension
     echo .............
     echo *
     cp ./rum.control ./rum--1.0.sql ./rum--1.2.sql ./rum--1.3.sql $out/share/extension
   '';
 }
