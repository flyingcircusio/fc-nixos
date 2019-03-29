{ system ? builtins.currentSystem
, nixpkgs ? (import ../versions.nix {}).nixpkgs
, pkgs ? import nixpkgs { inherit system; }
}:

let
  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  callTest = fn: args: pkgs.lib.hydraJob (importTest fn args system);

in {
  garbagecollect = callTest ./garbagecollect.nix {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  sudo = callTest ./sudo.nix {};
}
