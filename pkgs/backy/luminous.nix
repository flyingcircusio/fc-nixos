{
  pkgs ? import <nixpkgs> {},
  poetry2nix ? pkgs.poetry2nix,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  lzo ? pkgs.lzo,
  python310 ? pkgs.python310,
  ...
}:
let
 # src = ../path/to/checkout;
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "7bde3a1c9e7de33678d419ca104eb2acd739fe45";
    sha256 = "sha256-PDfLPzqRAgao6jiL8LgHCXi/si/58rZXhW6miLg91tI=";
  };

in poetry2nix.mkPoetryApplication {
    projectDir = src;
    src = src;
    doCheck = true;
    python = python310;
    extras = [];
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      python-lzo = super.python-lzo.overrideAttrs (old: {
        buildInputs = [ lzo ];
      });
      telnetlib3 = super.telnetlib3.overrideAttrs (old: {
        buildInputs = [ super.setuptools ];
      });
      pytest-flake8 = super.pytest-flake8.overrideAttrs (old: {
        buildInputs = [ super.setuptools ];
      });
      consulate = super.consulate.overrideAttrs (old: {
        buildInputs = [ super.setuptools ];
      });
    });
}
