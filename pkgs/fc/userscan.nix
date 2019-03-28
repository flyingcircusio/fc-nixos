{ pkgs
, docutils
, fetchFromGitHub
, lib
, makeRustPlatform
, recurseIntoAttrs
, rust_1_31
}:

let
  # switch back to default rustPlatform once upgraded to >= 19.03
  rustPlatform = recurseIntoAttrs (makeRustPlatform rust_1_31);

in rustPlatform.buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.3";

  src = fetchFromGitHub {
    name = "fc-userscan-src-${version}";
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "03jpkgzhlql4q1g3hhlkafk6q6q7cw2aqz2qcw4a8b37kpkidqi7";
  };

  cargoSha256 = "0jnqkl4g5m2rdlijf6hvns52rxpqagz5d9vhyny6w9clz3ssd14w";
  nativeBuildInputs = with pkgs; [ git docutils ];
  propagatedBuildInputs = with pkgs; [ lzo ];

  postBuild = ''
    substituteAll $src/userscan.1.rst $TMP/userscan.1.rst
    rst2man.py $TMP/userscan.1.rst > $TMP/userscan.1
  '';
  postInstall = ''
    install -D $TMP/userscan.1 $out/share/man/man1/fc-userscan.1
  '';

  meta = with lib; {
    description = "Scan and register Nix store references from arbitrary files";
    homepage = https://github.com/flyingcircusio/userscan;
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
