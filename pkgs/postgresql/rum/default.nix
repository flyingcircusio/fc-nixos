{ stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "rum";
  version = "1.3.13";

  src = fetchFromGitHub {
    rev = "1a4d4b8e2597483b8545f8111cb3c44e4be0aa73";
    owner = "postgrespro";
    repo = "rum";
    sha256 = "16jiykarnix9iis2gygn0nmfaxh2gxh794jwf69h7pgm0srz6376";
  };

  buildInputs = [ postgresql ];

  makeFlags = [
    "USE_PGXS=1"
  ];

   installPhase =
   ''
     mkdir -p $out/{bin,lib}
     cp ./rum.so $out/lib
     ext_dir=$out/share/postgresql/extension
     mkdir -p $ext_dir
     echo .............
     echo *
     cp ./rum.control ./rum--1.0.sql ./rum--1.2.sql ./rum--1.3.sql $ext_dir
   '';
 }
