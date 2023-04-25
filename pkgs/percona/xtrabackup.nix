{ lib, stdenv, fetchurl, bison, boost, cmake, curl, cyrus_sasl, libaio, libgcrypt
, libgpg-error, makeWrapper, pkg-config
, perlPackages
, libedit, libev, libevent, lz4, ncurses, vim, openssl, percona, procps
, protobuf, xxd, zlib }:

stdenv.mkDerivation rec {
  name = "xtrabackup-${version}";
  version = "8.0.32-26";

  src = fetchurl {
    url = "https://www.percona.com/downloads/Percona-XtraBackup-8.0/Percona-XtraBackup-${version}/source/tarball/percona-xtrabackup-${version}.tar.gz";
    sha256 = "sha256-KhwjSX/9WQXW3CC9tagB0bi66zJF7BHtEV3uDXi3peI=";
  };

  nativeBuildInputs = [ bison boost cmake makeWrapper pkg-config ];

  patches = [
    ./xtrabackup-abi-check.patch
  ];

  buildInputs = [
    (curl.override { inherit openssl; }) cyrus_sasl libaio libedit libev libevent libgcrypt libgpg-error lz4
    ncurses openssl procps protobuf xxd zlib
  ] ++ (with perlPackages; [ perl DBI DBDmysql ]);

  cmakeFlags = [
    "-DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock"
    "-DBUILD_CONFIG=xtrabackup_release"
    "-DINSTALL_MYSQLTESTDIR=OFF"
    "-DWITH_BOOST=system"
    "-DWITH_CURL=system"
    "-DWITH_EDITLINE=system"
    "-DWITH_LIBEVENT=bundled"
    "-DWITH_LZ4=system"
    "-DWITH_PROTOBUF=system"
    "-DWITH_SASL=system"
    "-DWITH_SSL=system"
    "-DWITH_ZLIB=system"
    "-DWITH_MAN_PAGES=OFF"
  ];

  postInstall = ''
    wrapProgram "$out"/bin/xtrabackup --prefix PERL5LIB : $PERL5LIB
    rm -r "$out"/lib/plugin/debug
  '';

  meta = with lib; {
    description = "Percona XtraBackup";
    homepage = https://www.percona.com/;
    license = licenses.lgpl2;
    platforms = platforms.linux;
  };
}
