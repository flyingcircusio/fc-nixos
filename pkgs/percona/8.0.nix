{ lib, stdenv, fetchurl, fetchFromGitHub, cmake, pkg-config, ncurses, zlib, xz
, lzo, lz4, bzip2, snappy
, libiconv, openssl, pcre, boost, judy, bison, libxml2
, libaio, jemalloc, cracklib, numactl, systemd
, asio, buildEnv, check, scons, curl, perl, cyrus_sasl, openldap, libtirpc
, rpcsvc-proto, DarwinTools, CoreServices, developer_cmds, cctools
, icu, libedit, libevent, protobuf, re2, readline, zstd, libfido2
}:

stdenv.mkDerivation rec {
  pname = "percona";
  version = "8.0.32-24";

  src = fetchurl {
    url = "https://www.percona.com/downloads/Percona-Server-8.0/Percona-Server-${version}/source/tarball/percona-server-${version}.tar.gz";
    sha256 = "sha256-KGdwbpFFl8s6UWF1FXPFRjyvg0NoTtfur8rR648tCB4=";
  };

  preConfigure = lib.optional stdenv.isDarwin ''
    ln -s /bin/ps $TMPDIR/ps
    export PATH=$PATH:$TMPDIR
    # XXX: Doesn't build on Darwin and I couldn't find out how to disable LDAP...
    rm -rf plugin/auth_ldap
  '';

  nativeBuildInputs = [ bison cmake pkg-config ]
    ++ lib.optionals (!stdenv.isDarwin) [ rpcsvc-proto ];

  ## NOTE: MySQL upstream frequently twiddles the invocations of libtool. When updating, you might proactively grep for libtool references.
  postPatch = ''
    substituteInPlace cmake/libutils.cmake --replace /usr/bin/libtool libtool
    substituteInPlace cmake/os/Darwin.cmake --replace /usr/bin/libtool libtool
  '';

  buildInputs = [
    boost (curl.override { inherit openssl; }) icu libedit libevent lz4 ncurses openssl protobuf re2 readline zlib
    zstd libfido2
  ] ++ lib.optionals stdenv.isLinux [
    numactl libtirpc openldap cyrus_sasl jemalloc systemd
  ] ++ lib.optionals stdenv.isDarwin [
    cctools CoreServices developer_cmds DarwinTools
  ];

  enableParallelBuilding = true;

  cmakeFlags = [

    "-DBUILD_CONFIG=mysql_release"
    "-DFEATURE_SET=community"
    "-DFORCE_UNSUPPORTED_COMPILER=1" # To configure on Darwin.

    "-DDEFAULT_CHARSET=utf8mb4"
    "-DDEFAULT_COLLATION=utf8mb4_unicode_ci"

    "-DWITH_ROUTER=OFF" # It may be packaged separately.
    "-DWITH_SYSTEM_LIBS=ON"
    "-DWITH_UNIT_TESTS=OFF"

    "-DWITH_ZLIB=system"
    "-DWITH_SSL=system"

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
    # Fails the SSE 4.2 check and forcing it doesn't work, too.
    "-DWITHOUT_ROCKSDB=1"
  ] ++ lib.optionals stdenv.isLinux [
    "-DWITH_JEMALLOC=1"
    "-DWITH_SYSTEMD=1"
  ];

  NIX_LDFLAGS = lib.optionalString stdenv.isLinux "-lgcc_s";
  CXXFLAGS = lib.optionalString stdenv.isi686 "-fpermissive";

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

  meta = with lib; {
    homepage = http://www.percona.com/;
    description = ''
      Is a free, fully compatible, enhanced, open source drop-in replacement for
      MySQL® that provides superior performance, scalability and instrumentation.
    '';
    platforms = platforms.unix;
  };
}
