{ lib
, docutils
, fetchFromGitHub
, lzo
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.8";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "095m0f05m5kfpnnvz2bllvfbb8kfabhcxanva4cl9b1i0z8ckvnn";
  };

  cargoHash = "sha256-2lPx02dOFNqfFaQPWpxrmycpdTt/FvfnZ/ve2/iBE7E=";
  nativeBuildInputs = [ docutils ];
  propagatedBuildInputs = [ lzo ];

  postBuild = ''
    substituteAll $src/userscan.1.rst $TMP/userscan.1.rst
    rst2man $TMP/userscan.1.rst > $TMP/userscan.1
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
