{ pkgs, stdenv, fetchFromGitHub, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.2";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "003ilmygqd675h3kkwpa236xkkzavx7ivjjaz1478gn25gxv8004";
  };

  cargoSha256 = "1jq0dhhk9hl3yx7038n4csahaxm6a0ycmrgyhl881i31w1p7ylvf";
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
  };
}
