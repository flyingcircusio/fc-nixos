{ system ? builtins.currentSystem
, nixpkgs ? (import ../nixpkgs.nix {}).nixpkgs
, pkgs ? import nixpkgs { inherit system; }
}:

let
  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  callTest = fn: args: pkgs.lib.hydraJob (importTest fn args system);

in {
  login = callTest ./login.nix {};
}
