{ rustPlatform, lib }:

rustPlatform.buildRustPackage {
  name = "roundcube-chpasswd";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = lib.cleanSource ./.;
  };
  cargoSha256 = "1fq49xvli5bpz3af5dyzizb1bmbz1fqw9z014fnb7g0snr8bls1a";
}
