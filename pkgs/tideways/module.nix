{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "5.7.4"; in

stdenv.mkDerivation {
  name = "tideways-php-module-${version}";

  builder = ./module-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/extension/${version}/tideways-php-${version}-x86_64.tar.gz";
    hash = "sha256-44NAfOFNhjzT6CUYKLAVVmx1PKG3EZI4w6tcwvCMirI=";
  };

  meta = {
    description = "The PHP extension module for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = lib.licenses.unfree;
  };
}
