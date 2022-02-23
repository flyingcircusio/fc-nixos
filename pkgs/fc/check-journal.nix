{ lib, fetchFromGitHub, rustPlatform, ronn, util-linux, systemd }:

with rustPlatform;

buildRustPackage rec {
  name = "check-journal-${version}";
  version = "838bf68aa87";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "check_journal";
    rev = version;
    sha256 = "1p4l1j1qh7chsrikkvhv86w6a5nxpqifhl55jmga8w30rv11x645";
  };

  cargoSha256 = "01rh6fc06issxghkvlb6m1gpyw5h3h4k6687chr4fjn4c39nhikb";

  # used in src/main.rs to set default path for journalctl
  JOURNALCTL = "${systemd}/bin/journalctl";

  nativeBuildInputs = [ ronn util-linux ];
  postBuild = "make man";

  preCheck = "patchShebangs fixtures/journalctl-cursor-file.sh";

  postInstall = ''
    install -m 0644 -D -t $out/share/man/man1 man/check_journal.1
    install -m 0644 -D -t $out/share/doc/check_journal README.md
  '';

  meta = with lib; {
    description = "Nagios/Icinga compatible plugin to search `journalctl` " +
      "output for matching lines.";
    homepage = "https://github.com/flyingcircusio/check_journal";
    maintainer = with maintainers; [ ckauhaus ];
    license = with licenses; [ bsd3 ];
  };
}
