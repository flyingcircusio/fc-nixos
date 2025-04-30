{ rustPlatform, lib }:

rustPlatform.buildRustPackage {
  name = "roundcube-chpasswd";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = lib.cleanSource ./.;
  };

  cargoHash = "sha256-6bEIW65Q6riDneU1HceNzBBmiBandH7L8aw9dvLwvKc=";
}
