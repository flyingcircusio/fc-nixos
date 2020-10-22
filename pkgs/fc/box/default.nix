{ stdenv, lib, rustPlatform, docutils }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "fc-box-${version}";
  version = "0.2.1";
  outputs = [ "out" "man" ];

  src = ./box;
  cargoSha256 = "0gvf8qkyg52f269vh7nxa55hi2aqpf0amcyk54li1ijya4s0qysw";

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
