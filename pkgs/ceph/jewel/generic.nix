{ stdenv, lib, ensureNewerSourcesHook, cmake, pkg-config
, which, git
, boost, pythonPackages
, libxml2, zlib
, openldap, lttng-ust
, babeltrace, gperf
, cunit, snappy
, makeWrapper, perl, leveldb
, libtool, autoconf, automake
, hdparm

# Optional Dependencies
, yasm ? null, fcgi ? null, expat ? null
, curl ? null, fuse ? null
, libedit ? null, libatomic_ops ? null, kinetic-cpp-client ? null
, libs3 ? null

# Mallocs
, jemalloc ? null, gperftools ? null

# Crypto Dependencies
, cryptopp ? null
, nss ? null, nspr ? null

# Linux Only Dependencies
, linuxHeaders, libuuid, udev, keyutils, libaio ? null, libxfs ? null
, zfs ? null

# Version specific arguments
, version, src ? [], buildInputs ? []
, ...
}:

# We must have one crypto library
assert cryptopp != null || (nss != null && nspr != null);

with stdenv;
with lib;
let

  shouldUsePkg = pkg_: let pkg = (builtins.tryEval pkg_).value;
    in if lib.any (lib.meta.platformMatch stdenv.hostPlatform) pkg.meta.platforms
      then pkg else null;

  optYasm = shouldUsePkg yasm;
  optFcgi = shouldUsePkg fcgi;
  optExpat = shouldUsePkg expat;
  optCurl = shouldUsePkg curl;
  optFuse = shouldUsePkg fuse;
  optLibedit = shouldUsePkg libedit;
  optLibatomic_ops = shouldUsePkg libatomic_ops;
  optKinetic-cpp-client = shouldUsePkg kinetic-cpp-client;
  optLibs3 = if versionAtLeast version "10.0.0" then null else shouldUsePkg libs3;

  optJemalloc = shouldUsePkg jemalloc;
  optGperftools = shouldUsePkg gperftools;

  optCryptopp = shouldUsePkg cryptopp;
  optNss = shouldUsePkg nss;
  optNspr = shouldUsePkg nspr;

  optLibaio = shouldUsePkg libaio;
  optLibxfs = shouldUsePkg libxfs;
  optZfs = shouldUsePkg zfs;

  hasRadosgw = optFcgi != null && optExpat != null && optCurl != null && optLibedit != null;

  # TODO: Reenable when kinetic support is fixed
  #hasKinetic = versionAtLeast version "9.0.0" && optKinetic-cpp-client != null;
  hasKinetic = false;

  # Malloc implementation (can be jemalloc, tcmalloc or null)
  malloc = if optJemalloc != null then optJemalloc else optGperftools;

  # We prefer nss over cryptopp
  cryptoStr = if optNss != null && optNspr != null then "nss" else
    if optCryptopp != null then "cryptopp" else "none";
  cryptoLibsMap = {
    nss = [ optNss optNspr ];
    cryptopp = [ optCryptopp ];
    none = [ ];
  };

  ceph-python-env = pythonPackages.python.withPackages (ps: [
    ps.sphinx
    ps.flask
    ps.cython
    ps.setuptools
    ps.pip
    # Libraries needed by the python tools
    # ps.Mako
    # ps.pecan
    ps.prettytable
    # ps.webob
    # ps.cherrypy
  ]);

in
stdenv.mkDerivation {
  name="ceph-${version}";

  inherit src;

  patches = [
    ./fc-jewel-snaptrim.patch
    ./fc-jewel-rewatch.patch
    ./fc-jewel-glibc2-32.patch
    ./fc-jewel-hdparm-naive-path.patch

    ./dont-use-virtualenvs.patch
  ];

  nativeBuildInputs = [
    perl libtool autoconf automake
    pkg-config which git pythonPackages.wrapPython makeWrapper
    (ensureNewerSourcesHook { year = "1980"; })
  ];

  buildInputs = buildInputs ++ cryptoLibsMap.${cryptoStr} ++ [
    boost ceph-python-env libxml2 optYasm optLibatomic_ops optLibs3
    malloc zlib openldap lttng-ust babeltrace gperf cunit
    snappy leveldb
  ] ++ optionals stdenv.isLinux [
    linuxHeaders libuuid udev keyutils optLibaio optLibxfs optZfs
  ] ++ optionals hasRadosgw [
    optFcgi optExpat optCurl optFuse optLibedit
  ] ++ optionals hasKinetic [
    optKinetic-cpp-client
  ];

  propagatedBuildInputs = [ hdparm ];

  preConfigure = ''
# require LD_LIBRARY_PATH for cython to find internal dep
export LD_LIBRARY_PATH="$PWD/build/lib:$LD_LIBRARY_PATH"

# requires setuptools due to embedded in-cmake setup.py usage
export PYTHONPATH="$(echo ${pythonPackages.setuptools}/lib/python*/site-packages/):$PYTHONPATH"

set -x
sed -e '/include ceph-detect-init/d' -i src/Makefile.am
sed -e '/include ceph-disk/d' -i src/Makefile.am

./autogen.sh

cat > src/ceph_ver.h << __EOF__
#ifndef CEPH_VERSION_H
#define CEPH_VERSION_H

#define CEPH_GIT_VER no_version
#define CEPH_GIT_NICE_VER "Development"

#endif
__EOF__
  '';

  configureFlags = [
    "--enable-gitversion=no"
    "--with-cython"
    "--with-eventfd"
    "--with-jemalloc"
    "--with-libaio"
    "--with-libatomic"
    "--with-mon"
    "--with-osd"
    "--with-nss"
    "--with-radosgw"
    "--with-rbd"
    "--with-rados"
    "--without-mds"
    "--with-xfs"
    "--without-cephfs"
    "--without-gtk"
    "--without-hadoop"
    "--without-kinetic"
    "--without-librocksdb"
    "--disable-cephfs-java"
    "--disable-coverage"
    "--with-systemd-unit-dir=/tmp"];

  cmakeFlags = [

    # "-DENABLE_GIT_VERSION=OFF"
    # "-DWITH_SYSTEM_BOOST=ON"

    # # enforce shared lib
    # "-DBUILD_SHARED_LIBS=ON"

    # # disable cephfs, cmake build broken for now
    # "-DWITH_CEPHFS=OFF"
    # # "-DWITH_LIBCEPHFS=OFF"

    # "-DWITH_OPENLDAP=OFF"

    # "-DKEYUTILS_INCLUDE_DIR=${keyutils}"
    # "-DUUID_INCLUDE_DIR=${libuuid}"
    # "-DCURL_INCLUDE_DIR=${curl}"
  ];

  postFixup = ''
    wrapPythonPrograms
  '';

  enableParallelBuilding = true;

  postInstall = ''
    source ${makeWrapper}/nix-support/setup-hook
    wrapProgram $out/bin/ceph-osd \
      --prefix PATH : ${lib.makeBinPath
        [ hdparm ] }
  '';

  # outputs = [ "dev" "lib" "out" "doc" ];

  meta = {
    homepage = https://ceph.com/;
    description = "Distributed storage system";
    license = licenses.lgpl21;
    maintainers = with maintainers; [ adev ak ];
    platforms = platforms.unix;
  };

  passthru = {
    inherit version;
    lib = {};
    codename = "jewel";
  };

}
