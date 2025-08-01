{ lib, rustPlatform }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-age-${version}";
  version = "0.2.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };

  cargoHash = "sha256-TK67iq1tv+L2DuYX7yNx4mY3O0SpcgUxzM/X6/TkkUo=";

  meta = {
    description = "Checks for outdated files and symlinks";
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
