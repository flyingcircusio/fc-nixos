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
    # TODO: this points to a branch head that only differs by the Nautilus-specific commits
    # from what we use for Luminous, but not the latest `main` head as that currently
    # fails to build in NixOS.
    rev = "7914012a4e74dfeca597f9dcde237de5ee2f41b0";
    sha256 = "sha256-EOWqQa//6UhvIIy3LGsFapmK2LMIBIQ90Om4XGOxS2g=";
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
