{ lib
, docutils
, fetchFromGitHub
, lzo
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.7";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "19jk0x03i0glsn96a26inbf7mznxzcadxvcsp5g9bilp28c4ibj3";
  };

  cargoSha256 = "0qvccpxgmk3pp35d9ivr4wwvfh4j6gi3ql04qb2icw19m93hna17";
  nativeBuildInputs = [ docutils ];
  propagatedBuildInputs = [ lzo ];

  postBuild = ''
    substituteAll $src/userscan.1.rst $TMP/userscan.1.rst
    rst2man.py $TMP/userscan.1.rst > $TMP/userscan.1
  '';
  postInstall = ''
    install -D $TMP/userscan.1 $out/share/man/man1/fc-userscan.1
  '';

  meta = with lib; {
    description = "Scan and register Nix store references from arbitrary files";
    homepage = "https://github.com/flyingcircusio/userscan";
    license = licenses.bsd3;
  };
}
