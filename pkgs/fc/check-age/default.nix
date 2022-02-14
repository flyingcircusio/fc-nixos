{ lib, rustPlatform }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-age-${version}";
  version = "0.2.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };
  cargoSha256 = "1dl9lm2xmzbrcqics8fsh8z2lqql086rd43f109gam1jlm0i8ajh";

  meta = {
    description = "Checks for outdated files and symlinks";
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
