{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "1.6.32"; in

stdenv.mkDerivation {
  name = "tideways-daemon-${version}";

  builder = ./daemon-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/daemon/${version}/tideways-daemon_linux_amd64-${version}.tar.gz";
    sha256 = "0ksnq6z89n9y8qyd46slia5ykqiwz7qvw53c9f9cyjbfbkqkzzzc";
  };

  meta = {
    description = "The daemon for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = lib.licenses.unfree;
  };
}
