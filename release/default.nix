# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs_ ? (import ../versions.nix { pkgs = import bootstrap {}; }).nixpkgs
, branch ? null  # e.g. "fc-23.11-dev"
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
, fc ? {
    outPath = ./.;
    revCount = 0;
    rev = "0000000000000000000000000000000000000000";
    shortRev = "0000000";
  }
, docObjectsInventory ? null
, scrubJobs ? true  # Strip most of attributes when evaluating
}:

with builtins;

with import "${nixpkgs_}/pkgs/top-level/release-lib.nix" {
  inherit supportedSystems scrubJobs;
  nixpkgsArgs = { config = { allowUnfree = true; inHydra = true; }; nixpkgs = nixpkgs_; };
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
        # default.nix is needed when the channel is imported directly, for example
        # from a fetchTarball.
        echo "{ ... }: import ./fc { nixpkgs = ./nixpkgs; }" > $out/nixos/default.nix
      ''];
      preferLocalBuild = true;
    };

  initialEnv =
    if stableBranch
    then branch
    else "fc-23.11-dev";

  initialNixChannels = pkgs.writeText "nix-channels" ''
    https://hydra.flyingcircus.io/channel/custom/flyingcircus/${initialEnv}/release nixos
  '';

  initialVMContents = [
    { source = initialNixChannels;
      target = "/root/.nix-channels";
    }
    {
      source = (pkgs.writeText "fc-agent-initial-run" ''
        VM ignores roles and just builds a minimal system while this marker file
        is present. This will be deleted during first agent run.
      '');
      target = "/etc/nixos/fc_agent_initial_run";
    }
    { source = ../nixos/etc_nixos_local.nix;
      target = "/etc/nixos/local.nix";
    }
  ];

  # Recursively searches for derivations and returns a list
  # of attribute paths as "dotted names", like "dns" or "fc.agent".
  # Traverses nested sets which have `recurseForDerivation = true;`.
  getDottedPackageNames =
    # Attrset with derivations, can have nested attrsets.
    attrs:
    # Path to a nested attrset as list of attr names, like [ "fc" ].
    # Empty list when we are processing top-level attrs.
    visitedAttrPath:
      filter
        (p: p != null)
        (lib.flatten
          ((lib.mapAttrsToList
            (n: v:
              let
                attrPath = visitedAttrPath ++ [n];
                dottedName = (lib.concatStringsSep "." attrPath);
                shouldRecurse = (isAttrs v && v.recurseForDerivations or false);
              in
                if lib.isDerivation v then dottedName
                else if shouldRecurse then getDottedPackageNames v attrPath
                else null)
            attrs)));

  # Exclude packages from being built by Hydra.
  # The exclusion list is applied to overlay packages and important packages.
  # Supports excluding packages from nested sets using "dotted names" like "fc.blockdev".
  excludedPkgNames = [
  ];

  overlay = import ../pkgs/overlay.nix pkgs pkgs;
  overlayPkgNames = getDottedPackageNames overlay [];
  overlayPkgNamesToTest = lib.subtractLists excludedPkgNames overlayPkgNames;

  importantPkgNames = fromJSON (readFile ../important_packages.json);
  importantPkgNamesToTest = lib.subtractLists excludedPkgNames importantPkgNames;

  # Results looks like: [ { python3Packages.requests.x86_64-linux = <job>; } ]
  pkgNameToHydraJobs = dottedName:
    let
      path = lib.splitString "." dottedName;
      job = lib.hydraJob (lib.attrByPath path null pkgs);
    in
      map
        (system: lib.setAttrByPath (path ++ [ system ]) job)
        supportedSystems;

  pkgNameListToHydraJobs = pkgNameList:
    # Merge the single-attribute sets from pkgNameToHydraJobs into one big attrset.
    lib.foldl'
      lib.recursiveUpdate
      {}
      (lib.flatten (map pkgNameToHydraJobs pkgNameList));

  platformRoleDoc =
  let
    html = import ../doc {
      inherit pkgs docObjectsInventory;
      branch = if branch != null then branch else "fc-${version}";
      updated = "${toString fc.revCount}.${shortRev}";
      failOnWarnings = true;
    };
  in lib.hydraJob (
    pkgs.runCommandLocal "platform-role-doc" { inherit html; } ''
      mkdir -p $out/nix-support
      tarball=$out/platform-role-doc.tar.gz
      tar czf $tarball --mode +w -C $html .
      echo "file tarball $tarball" > $out/nix-support/hydra-build-products
      cp $html/objects.inv $out
      echo "file inventory $out/objects.inv" >> $out/nix-support/hydra-build-products
    ''
  );

  doc = { roles = platformRoleDoc; };

  jobs = {
    pkgs = pkgNameListToHydraJobs overlayPkgNamesToTest;
    importantPackages = pkgNameListToHydraJobs importantPkgNamesToTest;
    tests = import ../tests { inherit system pkgs; nixpkgs = nixpkgs_; };
  };

  makeNetboot = config:
    let
      evaled = import "${nixpkgs_}/nixos/lib/eval-config.nix" config;
      build = evaled.config.system.build;
      kernelTarget = evaled.pkgs.stdenv.hostPlatform.linux-kernel.target;

      customIPXEScript = pkgs.writeTextDir "netboot.ipxe" ''
        #!ipxe

        set console ttyS2,115200

        :start
        menu Flying Circus Installer boot menu
        item --gap --          --- Info ---
        item --gap --           Console: ''${console}
        item --gap --          --- Settings ---
        item console_tty0      console=tty0
        item console_ttys1     console=ttyS1,115200
        item console_ttys2     console=ttyS2,115200
        item --gap --          --- Install ---
        item boot_installer    Boot installer
        item --gap --          --- Other ---
        item exit              Continue BIOS boot
        item local             Continue boot from local disk
        item shell             Drop to iPXE shell
        item reboot            Reboot computer

        choose selected
        goto ''${selected}
        goto error

        :console_tty0
        set console tty0
        goto start

        :console_ttys1
        set console ttyS1,115200
        goto start

        :console_ttys2
        set console ttyS2,115200
        goto start

        :local
        sanboot || goto error

        :reboot
        reboot

        :shell
        echo Type 'exit' to get the back to the menu
        shell
        set menu-timeout 0
        set submenu-timeout 0
        goto start

        :boot_installer
        kernel ${kernelTarget} init=${build.toplevel}/init console=''${console} initrd=initrd loglevel=4
        initrd initrd
        boot || goto error

        :error
        echo An error occured. Will fall back to menu in 15 seconds.
        sleep 15
        goto start
        '';
    in
      pkgs.symlinkJoin {
        name = "netboot-${evaled.config.system.nixos.label}-${system}";
        paths = [];
        postBuild = ''
          mkdir -p $out/nix-support
          cp ${build.netbootRamdisk}/initrd  $out/
          cp ${build.kernel}/${kernelTarget}  $out/
          cp ${customIPXEScript}/netboot.ipxe $out/

          echo "file ${kernelTarget} $out/${kernelTarget}" >> $out/nix-support/hydra-build-products
          echo "file initrd $out/initrd" >> $out/nix-support/hydra-build-products
          echo "file ipxe $out/netboot.ipxe" >> $out/nix-support/hydra-build-products
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
    constituents = collect isDerivation (jobs // { inherit channels; } );
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

    # iPXE netboot image
    netboot = lib.hydraJob (makeNetboot {
     inherit system;

     modules = [
       "${nixpkgs_}/nixos/modules/installer/netboot/netboot-minimal.nix"
       (import version_nix {})
       ./netboot-installer.nix
     ];
    });

    # VM image for the Flying Circus infrastructure.
    fc = lib.hydraJob (import "${nixpkgs_}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./vm-image.nix imgArgs)
        (import version_nix {})
        ../nixos
        ../nixos/roles
      ];
    }).config.system.build.fcImage;

    # VM image for devhost VMs
    dev-vm = lib.hydraJob (import "${nixpkgs_}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        (import ./dev-vm-image.nix imgArgs)
        (import version_nix {})
        ../nixos
        ../nixos/roles
      ];
    }).config.system.build.devVMImage;

  };

in

jobs // {
  inherit channels tested images doc;
  # Helpful for debugging with nix repl -f release/default.nix but should not included as Hydra jobs.
  # inherit excludedPkgNames overlayPkgNames importantPkgNames overlayPkgNamesToTest importantPkgNamesToTest;

  release = with lib; pkgs.releaseTools.channel rec {
    name = "release-${version}${versionSuffix}";
    src = combinedSources;
    constituents = [ src tested ];
    preferLocalBuild = true;

    passthru.src = combinedSources;

    patchPhase = "touch .update-on-nixos-rebuild";

    tarOpts = ''
      --owner=0 --group=0 \
      --mtime="1970-01-01 00:00:00 UTC" \
      --exclude-vcs-ignores \
    '';

    installPhase = ''
      mkdir -p $out/{tarballs,nix-support}
      tarball=$out/tarballs/nixexprs.tar

      # Add all files in nixos/ including hidden ones.
      # (-maxdepth 1: don't recurse into subdirs)
      find nixos/ -maxdepth 1 -type f -exec \
        tar uf "$tarball" --transform "s|^nixos|${name}|" ${tarOpts} {} \;

      # Add files from linked subdirectories. We want to keep the name of the
      # link in the archive, not the target. Example:
      # "nixos/fc/default.nix" becomes "release-23.11.2222.12abcdef/fc/default.nix"
      for d in nixos/*/; do
          tar uf "$tarball" --transform "s|^$d\\.|${name}/$(basename "$d")|" ${tarOpts} "$d."
      done

      # Compress using multiple cores and with "extreme settings" to reduce compressed size.
      xz -T0 -e "$tarball"

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
