{ lib, rustPlatform }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-age-${version}";
  version = "0.2.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };
  cargoSha256 = "0jnba2a2d7pw3j1fpyiz8x2sqw32hmfrvyh0y2vg6vhi3fj0n448";

  meta = {
    description = "Checks for outdated files and symlinks";
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
