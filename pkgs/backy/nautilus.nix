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
    rev = "94c5168c9a2f4e5a915ce8d1dedbedb1ef44061d";
    sha256 = "sha256-eDScuuD+04P7snR8H8tZm6E9e2XpTC16oBfDj7tIKCs=";
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
      consulate = pkgs.py_consulate python310.pkgs;
    });
}
