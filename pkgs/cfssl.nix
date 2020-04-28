{ stdenv, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  name = "cfssl-${version}";
  version = "1.4.1";

  goPackagePath = "github.com/cloudflare/cfssl";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "cfssl";
    rev = "v${version}";
    sha256 = "07qacg95mbh94fv64y577zyr4vk986syf8h5l8lbcmpr0zcfk0pd";
  };

  meta = with stdenv.lib; {
    homepage = https://cfssl.org/;
    description = "Cloudflare's PKI and TLS toolkit";
    license = licenses.bsd2;
  };
}
