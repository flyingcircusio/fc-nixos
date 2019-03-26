{ pkgs, stdenv, fetchFromGitHub, rustPlatform }:

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

  cargoDepsSha256 = "0znsf3f1nrfiivcszdzlz5gkxam2v97wyz5yil47z3109k3jlgp8";
  nativeBuildInputs = with pkgs; [ ronn ];
  OPENSSL_DIR = pkgs.openssl;

  postBuild = "make";
  postInstall = ''
    install -D check_journal.1 $out/share/man/man1/check_journal.1
  '';

  meta = with stdenv.lib; {
    description = "Nagios/Icinga compatible plugin to search `journalctl` " +
      "output for matching lines.";
    homepage = https://github.com/flyingcircusio/check_journal;
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
