{ stdenv, rust_1_31, recurseIntoAttrs, makeRustPlatform, docutils }:

with stdenv.lib;

let
  # switch back to default rustPlatform once upgraded to 19.03+
  rustPlatform = recurseIntoAttrs (makeRustPlatform rust_1_31);

in
rustPlatform.buildRustPackage rec {
  name = "fc-box-${version}";
  version = "0.2.1";
  outputs = [ "out" "man" ];

  src = ./box;
  cargoSha256 = "15lggzybljgrk9kqs672f0m6fl8zgax4f42a0vj38d0wv0pq1bfl";

  postBuild = ''
    substituteAllInPlace box.1.rst
    ${docutils}/bin/rst2man.py box.1.rst box.1
  '';

  postInstall = ''
    mkdir -p $man/share/man/man1
    mv box.1 $man/share/man/man1
  '';

  meta = {
    description = "Manage Flying Circus NFS boxes";
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
