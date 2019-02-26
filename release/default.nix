# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs ? (import ../nixpkgs.nix { pkgs = import bootstrap {}; }).nixpkgs
, fc ? { outPath = ./.; revCount = 0; rev = "00000000000"; shortRev = "0000000"; }
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
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
            version = "${version}${versionSuffix}";
            channelSources = allSources;
            contents = initialVMContents;
          })
          ../nixos
        ];
    }).config.system.build.virtualBoxOVA_FC);

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
    # The name `fc` if important because if channel is added without an
    # explicit name argument, it will be available as <fc>.
    fc = with lib; pkgs.releaseTools.channel {
      name = "fc-${version}${versionSuffix}";
      constituents = [ fcSrc ];
      src = fcSrc;
      patchPhase = ''
        echo -n "${version}" > .version
        echo -n "${versionSuffix}" > .version-suffix
        echo -n "${fc.rev}" > .git-revision
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

in

jobs // rec {
  inherit ova channels;

  tested = with lib; pkgs.releaseTools.aggregate {
    name = "tested";
    constituents = collect isDerivation (jobs // { inherit channels; });
    meta.description = "Indication that pkgs, tests and channels are fine";
  };

  release = with lib; pkgs.releaseTools.channel rec {
    CHANNELS =
      lib.mapAttrsToList (k: v: "${k} ${v.name} ${v.channelName} ${v}") channels;
    constituents = attrValues channels;
    src = constituents;
    name = "release-${version}${versionSuffix}";
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/{tarballs,nix-support}
      hbp="$out/nix-support/hydra-build-products"

      set -- ''${CHANNELS[@]}
      # 1=key (cleaned nix_name) 2=nix_name 3=channel_name 4=path
      while [[ -n "$1" ]]; do
        dest=$out/tarballs/$2.tar.xz
        cp $4/tarballs/nixexprs.tar.xz $dest
        echo "channel $1 $dest" >> $hbp
        echo "$2 $3" >> $out/nix-channels
        shift 4
      done

      echo "file - $out/nix-channels" >> $hbp
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
