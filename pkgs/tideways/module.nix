{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "5.4.42"; in

stdenv.mkDerivation {
  name = "tideways-php-module-${version}";

  builder = ./module-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/extension/${version}/tideways-php-${version}-x86_64.tar.gz";
    sha256 = "sha256-3o6jaH4AlHqa7/HEjKToVyTTFOffntYI8dy5QUXcYus";
  };

  meta = {
    description = "The PHP extension module for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = lib.licenses.unfree;
  };
}
