{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "1.7.28"; in

stdenv.mkDerivation {
  name = "tideways-daemon-${version}";

  builder = ./daemon-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/daemon/${version}/tideways-daemon_linux_amd64-${version}.tar.gz";
    sha256 = "sha256-9FezE7/yYiZmYC3PjPNMR6Lt0sqa5PMB2q3GK0H+1bY";
  };

  meta = {
    description = "The daemon for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = lib.licenses.unfree;
  };
}
