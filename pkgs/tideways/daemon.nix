{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "1.6.14"; in

stdenv.mkDerivation {
  name = "tideways-daemon-${version}";

  builder = ./daemon-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/daemon/${version}/tideways-daemon_linux_amd64-${version}.tar.gz";
    sha256 = "1fnhi63h7nk80fbzz7vw3dsgdb0bg1fa3g0zj3jr4xcmp48fdrz3";
  };

  meta = {
    description = "The daemon for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = stdenv.lib.licenses.unfree;
  };
}
