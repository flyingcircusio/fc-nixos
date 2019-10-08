{ stdenv, fetchurl, fetchFromGitHub, cmake, pkgconfig, ncurses, zlib, xz, lzo, lz4, bzip2, snappy
, libiconv, openssl, pcre, boost, judy, bison, libxml2
, libaio, jemalloc, cracklib, systemd, numactl
, asio, buildEnv, check, scons, curl, perl
}:

stdenv.mkDerivation rec {
  name = "percona-${version}";
  version = "8.0.16-7";

  src = fetchurl {
    url = "https://www.percona.com/downloads/Percona-Server-8.0/Percona-Server-${version}/source/tarball/percona-server-${version}.tar.gz";
    sha256 = "1677jm271l8jy7566r7lb5z1bfbfrc50yfkvggs58w4i4df6i3wg";
  };

  preConfigure = stdenv.lib.optional stdenv.isDarwin ''
    ln -s /bin/ps $TMPDIR/ps
    export PATH=$PATH:$TMPDIR
  '';

  nativeBuildInputs = [ cmake pkgconfig ];
  buildInputs = [
    ncurses openssl zlib pcre jemalloc libiconv libaio systemd boost curl perl
  ];

  enableParallelBuilding = true;

  cmakeFlags = [

    "-DBUILD_CONFIG=mysql_release"
    "-DDEFAULT_CHARSET=utf8mb4"
    "-DDEFAULT_COLLATION=utf8mb4_unicode_ci"

    "-DWITH_ZLIB=system"
    "-DWITH_SSL=system"
    "-DWITH_EDITLINE=bundled"

    # https://www.percona.com/blog/2013/03/08/mysql-performance-impact-of-memory-allocators-part-2/
    "-DWITH_JEMALLOC=1"
    "-DWITH_SYSTEMD=1"

    "-DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock"
    "-DMYSQL_DATADIR=/var/lib/mysql"
    "-DINSTALL_INFODIR=share/mysql/docs"
    "-DINSTALL_MANDIR=share/man"
    "-DINSTALL_PLUGINDIR=lib/mysql/plugin"
    "-DINSTALL_INCLUDEDIR=include/mysql"
    "-DINSTALL_DOCREADMEDIR=share/mysql"
    "-DINSTALL_SUPPORTFILESDIR=share/mysql"
    "-DINSTALL_MYSQLSHAREDIR=share/mysql"
    "-DINSTALL_DOCDIR=share/mysql/docs"
    "-DINSTALL_SHAREDIR=share/mysql"

    "-DENABLED_LOCAL_INFILE=ON"
    "-DWITH_ARCHIVE_STORAGE_ENGINE=1"
    "-DWITH_BLACKHOLE_STORAGE_ENGINE=1"
    "-DWITH_INNOBASE_STORAGE_ENGINE=1"
    "-DWITHOUT_EXAMPLE_STORAGE_ENGINE=1"
  ];

  NIX_LDFLAGS = stdenv.lib.optionalString stdenv.isLinux "-lgcc_s";
  CXXFLAGS = stdenv.lib.optionalString stdenv.isi686 "-fpermissive";

  prePatch = ''
    sed -i -e "s|/usr/bin/libtool|libtool|" cmake/libutils.cmake
    patchShebangs .
    sed -i "s|COMMAND env -i |COMMAND env -i PATH=$PATH |" \
      storage/rocksdb/CMakeLists.txt

    # Disable ABI check. See case #108154
    sed -i "s/SET(RUN_ABI_CHECK 1)/SET(RUN_ABI_CHECK 0)/" cmake/abi_check.cmake

  '';

  preBuild = ''
    export LD_LIBRARY_PATH=$(pwd)/library_output_directory
  '';

  postInstall = ''
    rm -r $out/mysql-test
    chmod g-w $out
  '';

  passthru.mysqlVersion = "8.0";

  meta = {
    homepage = http://www.percona.com/;
    description = ''
      Is a free, fully compatible, enhanced, open source drop-in replacement for
      MySQL® that provides superior performance, scalability and instrumentation.
    '';
  };
}
