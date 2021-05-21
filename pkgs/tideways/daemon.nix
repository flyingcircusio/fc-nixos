{ stdenv, fetchurl }:

assert stdenv.hostPlatform.system == "x86_64-linux";

let version = "1.6.16"; in

stdenv.mkDerivation {
  name = "tideways-daemon-${version}";

  builder = ./daemon-build.sh;

  src = fetchurl {
    url = "https://s3-eu-west-1.amazonaws.com/tideways/daemon/${version}/tideways-daemon_linux_amd64-${version}.tar.gz";
    sha256 = "0b1i9n7916vis26d75f119hxr0q89vps9hw7cqbx8473f31l6my3";
  };

  meta = {
    description = "The daemon for the Tideways profiling/debugging service.";
    homepage = "http://tideways.com";
    # license = lib.licenses.unfree;
  };
}
