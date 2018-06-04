{ pkgs, stdenv, fetchFromGitHub, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.1";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "1lflac09r34l6vk7nvca7kgh790f7fdpws1ibbq3r98x93skzj9s";
  };

  cargoSha256 = "1dnrnjk8nqw7wxwhsla3k5iyzkwd1plglqb4gf9r6193sba0rqm0";
  nativeBuildInputs = with pkgs; [ git docutils ];
  propagatedBuildInputs = with pkgs; [ lzo ];

  postBuild = ''
    substituteAll $src/userscan.1.rst $TMP/userscan.1.rst
    rst2man.py $TMP/userscan.1.rst > $TMP/userscan.1
  '';
  postInstall = ''
    install -D $TMP/userscan.1 $out/share/man/man1/fc-userscan.1
  '';

  meta = with stdenv.lib; {
    description = "Scan and register Nix store references from arbitrary files";
    homepage = https://github.com/flyingcircusio/userscan;
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
