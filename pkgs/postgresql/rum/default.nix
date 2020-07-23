{ stdenv, fetchFromGitHub, postgresql, postgresqlFromUnstable ? false }:

let
  # We use 12 from unstable which changed the location for extensions.
  extPath =
    if postgresqlFromUnstable
    then "share/postgresql/extension"
    else "share/extension";

in stdenv.mkDerivation {
  pname = "rum";
  version = "2020-04-07";

  src = fetchFromGitHub {
    rev = "bc917c9f0d667432412df998a3fe6b6c935b3053";
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
     ext_dir=$out/${extPath}
     mkdir -p $ext_dir
     echo .............
     echo *
     cp ./rum.control ./rum--1.0.sql ./rum--1.2.sql ./rum--1.3.sql $ext_dir
   '';
 }
