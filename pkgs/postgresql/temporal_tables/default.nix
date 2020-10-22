{ stdenv, fetchFromGitHub, pkgconfig, postgresql }:

stdenv.mkDerivation rec {
  name = "temporal_tables-${version}";
  version = "20190530-6cc86eb-git";

  src = fetchFromGitHub {
    owner = "mlt";
    repo = "temporal_tables";
    rev = "6cc86eb03d618d6b9fc09ae523f1a1e5228d22b5";
    sha256 = "0ykv37rm511n5955mbh9dcp7pgg88z1nwgszav7z6pziaj3nba8x";
  };

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = [ postgresql ];

  installPhase = ''
    mkdir -p $out/bin
    install -D temporal_tables.so -t $out/lib/
    install -D ./{temporal_tables-*.sql,temporal_tables.control} -t $out/share/postgresql/extension
  '';

  meta = with stdenv.lib; {
    description = "A PostgreSQL extension for temporal tables";
    longDescription = "This extension for PostgreSQL provides support for temporal tables. System-period data versioning (also known as transaction time or system time) allows you to specify that old rows are archived into another table (that is called the history table).";
    homepage = https://pgxn.org/dist/temporal_tables/;
    license = licenses.postgresql;
    maintainers = with maintainers; [ frlan ];
  };
}
