{ stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "rum";
  version = "1.3.7";

  src = fetchFromGitHub {
    rev = version;
    owner = "postgrespro";
    repo = "rum";
    sha256 = "185bmjd236qis5gqdv2vi52k5bg13cghs95ch5z0vqx59xqs17bm";
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
