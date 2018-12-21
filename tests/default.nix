{ system ? builtins.currentSystem
, pkgs ? import <nixpkgs> { inherit system; }
, nixpkgs ? pkgs.path
}:

let
  callTest = f: f.test;
  makeTest = import "${nixpkgs}/nixos/tests/make-test.nix";

in {
}
