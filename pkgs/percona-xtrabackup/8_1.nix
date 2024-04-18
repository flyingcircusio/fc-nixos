{ lib, stdenv, fetchurl, bison, boost, cmake, makeWrapper, pkg-config
, curl, cyrus_sasl, libaio, libedit, libev, libevent, libgcrypt, libgpg-error, lz4
, ncurses, numactl, openssl, procps, protobuf, valgrind, xxd, zlib
, perlPackages
, fetchSubmodules ? false, extraPatches ? [], extraPostInstall ? "", ...
}:

# TODO: rebase this onto the generic.nix when upstreaming
stdenv.mkDerivation (finalAttrs: {
  pname = "percona-xtrabackup";
  version = "8.1.0-1";

  src = fetchurl {
    url = "https://downloads.percona.com/downloads/Percona-XtraBackup-innovative-release/Percona-XtraBackup-${finalAttrs.version}/source/tarball/percona-xtrabackup-${finalAttrs.version}.tar.gz";
    hash = "sha256-4FjRjiqAg4lAqo+AoJVBPZlPWk6P9cFiKP2TgruCb+Y=";
  };

  nativeBuildInputs = [ bison boost cmake makeWrapper pkg-config ];

  buildInputs = [
    (curl.override { inherit openssl; }) cyrus_sasl libaio libedit libevent libev libgcrypt libgpg-error lz4
    ncurses numactl openssl procps protobuf valgrind xxd zlib
  ] ++ (with perlPackages; [ perl DBI DBDmysql ]);

  patches = extraPatches;

  cmakeFlags = [
    "-DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock"
    "-DBUILD_CONFIG=xtrabackup_release"
    "-DINSTALL_MYSQLTESTDIR=OFF"
    "-DWITH_BOOST=system"
    "-DWITH_CURL=system"
    "-DWITH_EDITLINE=system"
    "-DWITH_LIBEVENT=system"
    "-DWITH_LZ4=system"
    "-DWITH_PROTOBUF=system"
    "-DWITH_SASL=system"
    "-DWITH_SSL=system"
    "-DWITH_ZLIB=system"
    "-DWITH_VALGRIND=ON"
    "-DWITH_MAN_PAGES=OFF"
  ];

  postInstall = ''
    wrapProgram "$out"/bin/xtrabackup --prefix PERL5LIB : $PERL5LIB
    rm -r "$out"/lib/plugin/debug
  '' + extraPostInstall;

  meta = with lib; {
    description = "Non-blocking backup tool for MySQL";
    homepage = "http://www.percona.com/software/percona-xtrabackup";
    license = licenses.lgpl2;
    platforms = platforms.linux;
    maintainers = with maintainers; [ izorkin ];
  };
})
