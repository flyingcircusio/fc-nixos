# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs ? (import ../nixpkgs.nix { pkgs = import bootstrap {}; }).nixpkgs
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
, fc ? {
    outPath = ./.;
    revCount = 0;
    rev = "0000000000000000000000000000000000000000";
    shortRev = "0000000";
  }
, scrubJobs ? true  # Strip most of attributes when evaluating
}:

with builtins;

with import "${nixpkgs}/pkgs/top-level/release-lib.nix" {
  inherit supportedSystems scrubJobs;
  packageSet = import ../.;
};
# pkgs and lib imported from release-lib.nix

let
  shortRev = fc.shortRev or (substring 0 11 fc.rev);
  version = lib.fileContents "${nixpkgs}/.version";
  versionSuffix =
    (if stableBranch then "." else ".dev") +
    "${toString fc.revCount}.${shortRev}";
  version_nix = pkgs.writeText "version.nix" ''
    { ... }:
    {
      system.nixos.revision = "${fc.rev}";
      system.nixos.versionSuffix = "${versionSuffix}";
    }
  '';

  upstreamSources = (import ../nixpkgs.nix { pkgs = (import nixpkgs {}); });
  fcSrc = pkgs.stdenv.mkDerivation {
    name = "fc-overlay";
    src = lib.cleanSource ../.;
    builder = pkgs.stdenv.shell;
    PATH = with pkgs; lib.makeBinPath [ coreutils ];
    args = [ "-ec" ''
      cp -r $src $out
      chmod +w $out/nixos/version.nix
      cat ${version_nix} > $out/nixos/version.nix
    ''];
    preferLocalBuild = true;
  };

  combinedSources =
    pkgs.stdenv.mkDerivation {
      inherit fcSrc;
      inherit (upstreamSources) allUpstreams;
      name = "channel-sources-combined";
      builder = pkgs.stdenv.shell;
      PATH = with pkgs; lib.makeBinPath [ coreutils ];
      args = [ "-ec" ''
        mkdir -p $out/nixos
        cp -r $allUpstreams/* $out/nixos/
        ln -s $fcSrc $out/nixos/fc
        echo -n ${fc.rev} > $out/nixos/.git-revision
        echo -n ${version} > $out/nixos/.version
        echo -n ${versionSuffix} > $out/nixos/.version-suffix
      ''];
      preferLocalBuild = true;
    };

  initialNixChannels = pkgs.writeText "nix-channels" ''
    https://hydra.flyingcircus.io/channel/custom/flyingcircus/fc-${version}-dev/release nixos
  '';

  initialVMContents = [
    { source = initialNixChannels;
      target = "/root/.nix-channels";
    }
    { source = ../nixos/etc_nixos_local.nix;
      target = "/etc/nixos/local.nix";
    }
  ];

  modifiedPkgs = import ../pkgs/overlay.nix pkgs pkgs;

  jobs = {
    pkgs = mapTestOn (packagePlatforms modifiedPkgs);
    # inherit fc-manual tests;
  };

  channelsUpstream =
    lib.mapAttrs (name: src:
    let
      fullName =
        if (parseDrvName name).version != ""
        then "${src.name}.${substring 0 11 src.rev}"
        else "${src.name}-0.${substring 0 11 src.rev}";
    in pkgs.releaseTools.channel {
      inherit src;
      name = fullName;
      constituents = [ src ];
      patchPhase = ''
        echo -n "${src.rev}" > .git-revision
      '';
      passthru.channelName = src.name;
      meta.description = "${src.name} according to versions.json";
    })
    (removeAttrs upstreamSources [ "allUpstreams" ]);

  channels = channelsUpstream // {
    # The attribut ename `fc` if important because if channel is added without
    # an explicit name argument, it will be available as <fc>.
    fc = with lib; pkgs.releaseTools.channel {
      name = "fc-${version}${versionSuffix}";
      constituents = [ fcSrc ];
      src = fcSrc;
      patchPhase = ''
        echo -n "${fc.rev}" > .git-revision
        echo -n "${versionSuffix}" > .version-suffix
        echo -n "${version}" > .version
      '';
      passthru.channelName = "fc";
      meta = {
        description = "Main channel of the <fc> overlay";
        homepage = "https://flyingcircus.io/doc/";
        license = [ licenses.bsd3 ];
        maintainer = with maintainers; [ ckauhaus ];
      };
    };
  };

  tested = with lib; pkgs.releaseTools.aggregate {
    name = "tested";
    constituents = collect isDerivation (jobs // { inherit channels; });
    meta.description = "Indication that pkgs, tests and channels are fine";
  };

  images =
    let
      imgArgs = {
        inherit nixpkgs;
        version = "${version}${versionSuffix}";
        channelSources = combinedSources;
        configFile = ../nixos/etc_nixos_local.nix;
        contents = initialVMContents;
      };
    in
    {
    # A bootable VirtualBox OVA (i.e. packaged OVF image).
    ova = lib.hydraJob (import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./ova-image.nix imgArgs)
        (import version_nix {})
        ../nixos
      ];
    }).config.system.build.ovaImage;

    # VM image for the Flying Circus infrastructure.
    fc = lib.hydraJob (import "${nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./fc-image.nix imgArgs)
        (import version_nix {})
        ../nixos
      ];
    }).config.system.build.fcImage;
    };

in

jobs // {
  inherit channels tested images;

  release = with lib; pkgs.releaseTools.channel rec {
    name = "release-${version}${versionSuffix}";
    src = combinedSources;
    constituents = [ src tested ];
    preferLocalBuild = true;
    patchPhase = "touch .update-on-nixos-rebuild";

    XZ_OPT = "-1";
    tarOpts = ''
      --owner=0 --group=0 --mtime="1970-01-01 00:00:00 UTC" \
      --exclude-vcs-ignores \
      --transform='s!^\.!${name}!' \
    '';

    installPhase = ''
      mkdir -p $out/{tarballs,nix-support}
      cd nixos
      tar cJhf $out/tarballs/nixexprs.tar.xz ${tarOpts} .

      echo "channel - $out/tarballs/nixexprs.tar.xz" > "$out/nix-support/hydra-build-products"
      echo $constituents > "$out/nix-support/hydra-aggregate-constituents"

      # Propagate build failures.
      for i in $constituents; do
        if [ -e "$i/nix-support/failed" ]; then
          touch "$out/nix-support/failed"
        fi
      done
    '';
  };
}
