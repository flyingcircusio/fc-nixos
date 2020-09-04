{ lib, rustPlatform }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-age-${version}";
  version = "0.1.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };
  cargoSha256 = "04ad2x3f225zn2x4lv9h7d5ys9xwrfgyknnkgr3qa8i75kmydbd8";

  meta = {
    description = "Checks for outdated files and symlinks";
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
