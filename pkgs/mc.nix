{ pkgs ? import <nixpkgs> { }
, python34Packages ? pkgs.python34Packages
, stdenv ? pkgs.stdenv
, lib ? pkgs.lib
, fetchurl ? pkgs.fetchurl
}:

stdenv.mkDerivation rec {
  name = "mc-${version}";
  version = "4.8.22";

  src = fetchurl {
    url = "http://ftp.midnight-commander.org/mc-${version}.tar.bz2";
    sha256 = "0cdl33r6vz5amvmlsgh3kc2fsi0lhvwzw1bs67yssrwr6rsir7wd";
  };

  propagatedBuildInputs = [
    pkgs.glib
  ];

  buildInputs = [
    pkgs.pkgconfig
    pkgs.slang
    pkgs.perl
   ];

  enableParallelBuilding = true;
  configureFlagsArray = [
    ];
  meta = {
    homepage = http://www.midnight-commander.org;
    description = "GNU Midnight Commander is a visual file manager.";
  };
}
