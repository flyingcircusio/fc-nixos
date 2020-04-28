{ stdenv, buildGoPackage, fetchFromGitHub, fetchpatch }:

buildGoPackage rec {
  version = "3.0.0";
  pname = "certmgr";

  goPackagePath = "github.com/cloudflare/certmgr/";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "certmgr";
    rev = "v${version}";
    sha256 = "0v1sxp7qalbf4mjlxd718r40b4y2406xd6pihs5av22zznl17sn3";
  };

  meta = with stdenv.lib; {
    homepage = https://cfssl.org/;
    description = "Cloudflare's certificate manager";
    license = licenses.bsd2;
  };
}
