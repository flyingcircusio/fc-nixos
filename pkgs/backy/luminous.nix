{
  pkgs ? import <nixpkgs> {},
  poetry2nix ? pkgs.poetry2nix,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  lzo ? pkgs.lzo,
  ...
}:
let src = fetchFromGitHub {
  owner = "flyingcircusio";
  repo = "backy";
  rev = "9ff642ab45f295984bbac797509921c76c3a0e2b";
  sha256 = "sha256:085ll6mrvk02kzmhyz75ld61mx5brrk78wlcgbapd78vyb7x30c8";
};
in poetry2nix.mkPoetryApplication {
    projectDir = src;
    src = src;
    doCheck = true;
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      python-lzo = super.python-lzo.overrideAttrs (old: {
        buildInputs = [ lzo ];
      });
    });
}
