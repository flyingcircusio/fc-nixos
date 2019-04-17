{ system ? builtins.currentSystem
, nixpkgs ? (import ../versions.nix {}).nixpkgs
, pkgs ? import nixpkgs { inherit system; }
}:

with pkgs.lib;

let
  # test calling code copied from nixos/release.nix
  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  callTest = fn: args: hydraJob (importTest fn args system);

  callSubTests = fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;
  in discover (importTest fn args system);

in {
  garbagecollect = callTest ./garbagecollect.nix {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  network = callSubTests ./network {};
  prometheus = callTest ./prometheus.nix {};
  statshost-master = callTest ./statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  webproxy = callTest ./webproxy.nix {};
}
