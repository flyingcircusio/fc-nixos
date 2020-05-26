{ rustPlatform, lib }:

rustPlatform.buildRustPackage {
  name = "roundcube-chpasswd";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = lib.cleanSource ./.;
  };
  cargoSha256 = "1rpxgpfcc17m499mx2zww4n5absjhk747zs9sqs3x98dgzz1kx5w";
}
