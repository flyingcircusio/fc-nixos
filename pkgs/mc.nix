{ stdenv
, fetchurl
, glib
, perl
, pkgconfig
, slang
}:

stdenv.mkDerivation rec {
  name = "mc-${version}";
  version = "4.8.24";

  src = fetchurl {
    url = "http://ftp.midnight-commander.org/${name}.tar.bz2";
    sha256 = "0d5f9g4a10w1yaqp7nb46bm4frnk5rhp3gx88n3aihyh8q2lvk6g";
  };

  propagatedBuildInputs = [ glib ];
  buildInputs = [ pkgconfig slang perl ];

  enableParallelBuilding = true;
  meta = {
    homepage = http://www.midnight-commander.org;
    description = "GNU Midnight Commander is a visual file manager.";
  };
}
