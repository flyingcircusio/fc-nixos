{ lib, buildGoPackage, fetchFromGitHub, fetchpatch }:

buildGoPackage rec {
  version = "3.0.3";
  pname = "certmgr";

  goPackagePath = "github.com/cloudflare/certmgr/";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "certmgr";
    rev = "v${version}";
    sha256 = "09wsggr1ydrqk7fbad7dbi6i9pvj4q3ql9zmfmnpvgwv9r9ly0rj";
  };

  meta = with lib; {
    homepage = https://cfssl.org/;
    description = "Cloudflare's certificate manager";
    license = licenses.bsd2;
  };
}
