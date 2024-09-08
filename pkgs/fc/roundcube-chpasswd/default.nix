{ rustPlatform, lib }:

rustPlatform.buildRustPackage {
  name = "roundcube-chpasswd";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = lib.cleanSource ./.;
  };
  cargoHash = "sha256-vPQZ/n8NpT401kn/Q86EUi9VLOH8i15TIvUExtx9/eY";
}
