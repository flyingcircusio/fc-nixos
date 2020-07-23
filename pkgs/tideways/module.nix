{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "5.1.18"; in

stdenv.mkDerivation {
  name = "tideways-php-module-${version}";

  builder = ./module-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/extension/${version}/tideways-php-${version}-x86_64.tar.gz";
    sha256 = "0nrpdkwb87xj6ampxslgvz320ihd94bh342bxbvmi9022w3ibv83";
  };

  meta = {
    description = "The PHP extension module for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = stdenv.lib.licenses.unfree;
  };
}
