# Usage example: `nix-build release.nix -A nixos.channel`
{ supportedSystems ? [ "x86_64-linux" ]
, ...  } @ args:
let
  # source tree
  nixpkgsSrc = import ./nixpkgs.nix {};

  # attrset w/ overlay
  pkgs = import nixpkgsSrc { overlays = [ (import ./fc/pkgs/overlay.nix) ]; };

  lib = pkgs.lib;

  # special source tree which includes ./fc
  # this is normally not necessary since we use fc/pkg/overlay.nix
  channel = let
    src = import ./nixpkgs.nix { channelExtras = { fc = ./fc; }; };
  in
    (import "${src}/nixos/release.nix" {
      inherit supportedSystems;
    }).channel;

in

with builtins;
rec {
  nixos = (import "${nixpkgsSrc}/nixos/release.nix" {
    inherit supportedSystems;
  }) // { inherit channel; };

  nixpkgs = removeAttrs
    (import "${nixpkgsSrc}/pkgs/top-level/release.nix" {
      inherit supportedSystems;
    })
    [ "unstable" ];

  fc = {
    tests = import ./fc/tests {
      inherit pkgs lib supportedSystems nixpkgsSrc;
      inherit (nixos) callTest callSubTests;
    };

    # locally added or changed packages
    pkgs = lib.filterAttrs (n: v: lib.isDerivation v)
      (lib.mapAttrs
        (name: v: pkgs.${name})
        (import fc/pkgs/overlay.nix pkgs pkgs));
  };

  tested = pkgs.lib.hydraJob (pkgs.releaseTools.aggregate {
    name = "nixos-${nixos.channel.version}";
    meta = {
      description = "Release-critical builds for the NixOS channel";
    };
    constituents =
      let
        all = x: map (system: x.${system}) supportedSystems;
      in [
        nixos.channel

        (all nixos.tests.env)
        (all nixos.tests.login)
        (all nixos.tests.misc)
        (all nixos.tests.nat.firewall)
        (all nixos.tests.nat.firewall-conntrack)
        (all nixos.tests.networking.scripted.loopback)
        (all nixos.tests.networking.scripted.static)
        (all nixos.tests.networking.scripted.dhcpSimple)
        (all nixos.tests.networking.scripted.dhcpOneIf)
        (all nixos.tests.networking.scripted.bond)
        (all nixos.tests.networking.scripted.bridge)
        (all nixos.tests.networking.scripted.macvlan)
        (all nixos.tests.networking.scripted.sit)
        (all nixos.tests.networking.scripted.vlan)
        (all nixos.tests.nfs4)
        (all nixos.tests.openssh)
        (all nixos.tests.php-pcre)
        (all nixos.tests.proxy)
        (all nixos.tests.simple)
        (all nixos.tests.slim)
        (all nixos.tests.switchTest)
        (all nixos.tests.udisks2)
      ]
      ++ (attrValues fc.tests)
      ++ (attrValues fc.pkgs);
  });

}
