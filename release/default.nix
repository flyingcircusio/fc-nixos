# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs ? (import ../nixpkgs.nix { pkgs = import bootstrap {}; }).nixpkgs
, fc ? { outPath = ./.; revCount = 1; rev = "0000000"; }
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
, scrubJobs ? true  # Strip most of attributes when evaluating
}:

with import "${nixpkgs}/pkgs/top-level/release-lib.nix" {
  inherit supportedSystems scrubJobs;
  packageSet = import ../.;
};
# pkgs and lib imported from release-lib.nix

let
  version = lib.fileContents "${nixpkgs}/.version";
  versionSuffix =
    (if stableBranch then "." else "beta") + "${toString fc.revCount}.${fc.rev}";

  versionModule = {
    system.nixos.versionSuffix = versionSuffix;
    system.nixos.revision = fc.rev;
  };

  fcSrc = lib.cleanSource ../.;

  upstreamSources = (import ../nixpkgs.nix { pkgs = (import nixpkgs {}); });

  allSources =
    lib.hydraJob (
      pkgs.stdenv.mkDerivation {
        inherit fcSrc;
        inherit (upstreamSources) all;
        name = "channel-sources-fc";
        builder = pkgs.stdenv.shell;
        PATH = with pkgs; lib.makeBinPath [ coreutils ];
        args = [ "-ec" ''
          mkdir $out
          cp -r $all/* $out
          ln -s $fcSrc $out/fc
        ''];
        preferLocalBuild = true;
      });

  initialVMContents = [
    {
      source = ../nixos/etc_nixos_local.nix;
      target = "/etc/nixos/local.nix";
    }
  ];

  nixpkgs' = import ../pkgs/overlay.nix pkgs pkgs;

  # A bootable VirtualBox OVA (i.e. packaged OVF image).
  ova =
    lib.hydraJob ((import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules =
        [ versionModule
          (import ./ova.nix {
            inherit nixpkgs;
            channelSources = allSources;
            contents = initialVMContents;
          })
          ../nixos/platform
        ];
    }).config.system.build.virtualBoxOVA);

  jobs = {
    pkgs = mapTestOn (packagePlatforms nixpkgs');
    # inherit tests manual;
  };

in

jobs
//
rec {
  inherit ova;

  channels = (
    lib.mapAttrs (name: src: (
      pkgs.releaseTools.channel {
        inherit src;
        name = src.name;
        constituents = [ src ];
        meta.description = "${src.name} channel";
      }))
      upstreamSources
  ) // {
    # The name `fc` if important because if channel is added without an
    # explicit name argument, it will be available as <fc>.
    fc = pkgs.releaseTools.channel {
      name = "fc";
      constituents = lib.collect lib.isDerivation (jobs // upstreamSources);
      src = fcSrc;
      meta.description = "Main channel of the <fc> overlay";
    };
  };
}
