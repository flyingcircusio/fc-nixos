# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs ? (import ../nixpkgs.nix { pkgs = import bootstrap {}; }).nixpkgs
, fc ? { outPath = ./.; revCount = 0; rev = "00000000000"; }
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
  shortRev = builtins.substring 0 11 fc.rev;
  version = lib.fileContents "${nixpkgs}/.version";
  versionSuffix =
    (if stableBranch then "." else ".dev") +
    "${toString fc.revCount}.${shortRev}";

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
        inherit (upstreamSources) allUpstreams;
        name = "channel-sources-fc";
        builder = pkgs.stdenv.shell;
        PATH = with pkgs; lib.makeBinPath [ coreutils ];
        args = [ "-ec" ''
          mkdir $out
          cp -r $allUpstreams/* $out
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

  # A bootable VirtualBox OVA (i.e. packaged OVF image).
  ova =
    lib.hydraJob ((import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
          (import ./ova.nix {
            inherit nixpkgs;
            channelSources = allSources;
            contents = initialVMContents;
          })
          ../nixos
          versionModule
        ];
    }).config.system.build.virtualBoxOVA);

  nixpkgsCustomized = import ../pkgs/overlay.nix pkgs pkgs;

  jobs = {
    pkgs = mapTestOn (packagePlatforms nixpkgsCustomized);
    # inherit tests manual;
  };

  channelsUpstream = lib.mapAttrs
    (name: src: pkgs.releaseTools.channel {
      inherit src;
      name = src.name;
      constituents = [ src ];
      isNixOS = true;
      meta.description = "${src.name} according to versions.json";
    })
    (removeAttrs upstreamSources [ "allUpstreams" ]);

  channels = channelsUpstream // {
    # The name `fc` if important because if channel is added without an
    # explicit name argument, it will be available as <fc>.
    fc = with lib; pkgs.releaseTools.channel {
      name = "fc-${version}${versionSuffix}";
      constituents = [ (attrValues channelsUpstream) ];
      src = fcSrc;
      patchPhase = ''
        touch .update-on-nixos-rebuild
        echo "${version}" > .version
        echo "${versionSuffix}" > .version-suffix
        echo "${fc.rev}" > .git-revision
      '';
      meta = {
        description = "Main channel of the <fc> overlay";
        homepage = "https://flyingcircus.io/doc/";
        license = [ licenses.bsd3 ];
        maintainer = with maintainers; [ ckauhaus ];
      };
    };
  };

in

jobs // {
  inherit ova channels;

  tested = with lib; pkgs.releaseTools.aggregate {
    name = "tested-${version}${versionSuffix}";
    constituents = collect isDerivation (jobs // { inherit channels; });
    meta.description = "Indication that pkgs, tests and channels are fine";
  };
}
