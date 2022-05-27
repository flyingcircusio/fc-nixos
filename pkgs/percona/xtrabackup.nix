{ stdenv, fetchurl, boost, bison, cmake, curl, libaio, libgcrypt, libgpg-error, libev, ncurses, vim, percona, ... }:

stdenv.mkDerivation rec {
  name = "xtrabackup-${version}";
  version = "8.0.28-21";

  src = fetchurl {
    url = "https://www.percona.com/downloads/Percona-XtraBackup-8.0/Percona-XtraBackup-${version}/source/tarball/percona-xtrabackup-${version}.tar.gz";
    sha256 = "sha256-ZtfxX45h0CMcvIFN/3P8YYHtmqkdVbFKNKWzK2PoygI=";
  };

  buildInputs = [
    bison
    boost
    cmake
    curl
    libaio
    libev
    libgcrypt
    libgpg-error
    ncurses
    percona
    vim
  ];

  enableParallelBuilding = true;
  cmakeFlags = [
    "-DBUILD_CONFIG=xtrabackup_release"
    "-DGCRYPT_LIB_PATH=${libgcrypt}/lib:${libgpg-error}/lib"
    "-DWITH_MAN_PAGES=OFF"
  ];

  prePatch = ''
    # Disable ABI check. See case #108154
    sed -i "s/SET(RUN_ABI_CHECK 1)/SET(RUN_ABI_CHECK 0)/" cmake/abi_check.cmake

  '';

  preBuild = ''
    export LD_LIBRARY_PATH=$(pwd)/library_output_directory
  '';

  postInstall = ''
    chmod g-w $out
  '';

  meta = {
    homepage = https://www.percona.com/;
    description = "Percona XtraBackup";
  };
}
