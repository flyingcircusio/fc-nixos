{ stdenv, fetchurl, pkgconfig, postgresql }:

stdenv.mkDerivation rec {
  name = "temporal_tables-${version}";
  version = "1.2.0";

  src = fetchurl {
    url = "https://github.com/arkhipov/temporal_tables/archive/v1.2.0.tar.gz";
    sha256 = "e6d1b31a124e8597f61b86f08b6a18168f9cd9da1db77f2a8dd1970b407b7610";
  };

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = [ postgresql ];

  installPhase = ''
    mkdir -p $out/bin
    install -D temporal_tables.so -t $out/lib/
    install -D ./{temporal_tables-*.sql,temporal_tables.control} -t $out/share/extension
  '';

  meta = with stdenv.lib; {
    description = "A PostgreSQL extension for temporal tables";
    longDescription = "This extension for PostgreSQL provides support for temporal tables. System-period data versioning (also known as transaction time or system time) allows you to specify that old rows are archived into another table (that is called the history table).";
    homepage = https://pgxn.org/dist/temporal_tables/;
    license = licenses.postgresql;
    maintainers = with maintainers; [ frlan ];
  };
}
