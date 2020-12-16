# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs_ ? (import ../versions.nix { pkgs = import bootstrap {}; }).nixpkgs
, branch ? null  # e.g. "fc-20.09-dev"
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

with import "${nixpkgs_}/pkgs/top-level/release-lib.nix" {
  inherit supportedSystems scrubJobs;
  nixpkgsArgs = { config = { allowUnfree = false; inHydra = true; }; nixpkgs = nixpkgs_; };
  packageSet = import ../.;
};
# pkgs and lib imported from release-lib.nix

let
  shortRev = fc.shortRev or (substring 0 11 fc.rev);
  version = lib.fileContents "${nixpkgs_}/.version";
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

  upstreamSources = (import ../versions.nix { pkgs = (import nixpkgs_ {}); });
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

  modifiedPkgNames = attrNames (import ../pkgs/overlay.nix pkgs pkgs);

  excludedPkgNames = [
    # Build fails with patch errors.
    "gitlab"
    "gitlab-workhorse"
    # The kernel universe is _huge_ and contains a lot of unfree stuff. Kernel
    # packages which are really needed are pulled in as dependencies anyway.
    "linux"
    "linux_5_4"
    "linuxPackages"
    "linuxPackages_5_4"
    # Same as above, don't pull everything in here
    "python2Packages"
    "python27Packages"
    "python3Packages"
    "python37Packages"
    "python38Packages"
  ];

  includedPkgNames = [
    "calibre"
  ];

  testPkgNames = includedPkgNames ++
    lib.subtractLists excludedPkgNames modifiedPkgNames;

  testPkgs =
    listToAttrs (map (n: { name = n; value = pkgs.${n}; }) testPkgNames);

  platformRoleDoc =
  let
    html = import ../doc {
      inherit pkgs;
      branch = if branch != null then branch else "fc-${version}";
      updated = "${toString fc.revCount}.${shortRev}";
    };
  in lib.hydraJob (
    pkgs.runCommandLocal "platform-role-doc" { inherit html; } ''
      mkdir -p $out/nix-support
      tarball=$out/platform-role-doc.tar.gz
      tar czf $tarball -C $html .
      echo "file tarball $tarball" > $out/nix-support/hydra-build-products
    ''
  );

  jobs = {
    pkgs = mapTestOn (packagePlatforms testPkgs);
    tests = import ../tests { inherit system pkgs; nixpkgs = nixpkgs_; };
    doc = platformRoleDoc;
  };

  makeNetboot = config:
    let
      evaled = import "${nixpkgs_}/nixos/lib/eval-config.nix" config;
      build = evaled.config.system.build;
      kernelTarget = evaled.pkgs.stdenv.hostPlatform.platform.kernelTarget;
    in
      pkgs.symlinkJoin {
        name = "netboot-${evaled.config.system.nixos.label}-${system}";
        paths = [
          build.netbootRamdisk
          build.kernel
          build.netbootIpxeScript
        ];
        postBuild = ''
          mkdir -p $out/nix-support
          echo "file ${kernelTarget} ${build.kernel}/${kernelTarget}" >> $out/nix-support/hydra-build-products
          echo "file initrd ${build.netbootRamdisk}/initrd" >> $out/nix-support/hydra-build-products
          echo "file ipxe ${build.netbootIpxeScript}/netboot.ipxe" >> $out/nix-support/hydra-build-products
        '';
        preferLocalBuild = true;
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
        nixpkgs = nixpkgs_;
        version = "${version}${versionSuffix}";
        channelSources = combinedSources;
        configFile = ../nixos/etc_nixos_local.nix;
        contents = initialVMContents;
      };
    in
    {
    # A bootable VirtualBox OVA (i.e. packaged OVF image).
    ova = lib.hydraJob (import "${nixpkgs_}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./ova-image.nix imgArgs)
        (import version_nix {})
        ../nixos
      ];
    }).config.system.build.ovaImage;

    vagrant = lib.hydraJob (import "${nixpkgs_}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./ova-image.nix (imgArgs // {infrastructureModule = "vagrant"; }))
        (import version_nix {})
        ../nixos
      ];
    }).config.system.build.ovaImage;

    # iPXE netboot image
    netboot = makeNetboot {
      inherit system;
      modules = [
        "${nixpkgs_}/nixos/modules/installer/netboot/netboot-minimal.nix"
        (import version_nix {})
      ];
    };

    # VM image for the Flying Circus infrastructure.
    fc = lib.hydraJob (import "${nixpkgs_}/nixos/lib/eval-config.nix" {
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
