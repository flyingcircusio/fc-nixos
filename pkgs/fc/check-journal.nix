{ stdenv, fetchFromGitHub, rustPlatform, openssl, ronn }:

with rustPlatform;

buildRustPackage rec {
  name = "check-journal-${version}";
  version = "1.0.5";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "check_journal";
    rev = version;
    sha256 = "1b4sy6kykav751jrjifism1n6xx8xfm7s7fvcaanmwrxq7j9ixxl";
  };

  cargoSha256 = "091yr17df0qf2n4dv0xifrv25z774ikmw9ysk4kd8xl2shijkxr9";
  nativeBuildInputs = [ ronn ];
  OPENSSL_DIR = openssl.dev;
  OPENSSL_LIB_DIR = "${openssl.out}/lib";

  postBuild = "make";
  postInstall = ''
    install -D check_journal.1 $out/share/man/man1/check_journal.1
  '';

  meta = with stdenv.lib; {
    description = "Nagios/Icinga compatible plugin to search `journalctl` " +
      "output for matching lines.";
    homepage = https://github.com/flyingcircusio/check_journal;
    license = with licenses; [ bsd3 ];
  };
}
