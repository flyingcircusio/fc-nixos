{ lib
, docutils
, fetchFromGitHub
, lzo
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.4";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "172q2ywdpg3q7picbl99cv45rcca2vhl7pvb7d4ilc66mhq6b265";
  };

  cargoSha256 = "0rb181fih70jmnpn9q5lhwhv2gk0rk58945g6j6gapapq4sf259m";
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
