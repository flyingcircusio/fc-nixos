# everything in release/ MUST NOT import from <nixpkgs> to get repeatable builds
{ system ? builtins.currentSystem
, bootstrap ? <nixpkgs>
, nixpkgs_ ? (import ../versions.nix { pkgs = import bootstrap {}; }).nixpkgs
, branch ? null  # e.g. "fc-24.05-dev"
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
    else "fc-24.05-dev";

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
    "discourse"
    "mc"
  ];

  overlay = import ../pkgs/overlay.nix pkgs pkgs;
  overlayPkgNames = getDottedPackageNames overlay [];
  overlayPkgNamesToTest = lib.subtractLists excludedPkgNames overlayPkgNames;

  importantPkgNames = fromJSON (readFile ../release/important_packages.json);
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
      inherit pkgs;
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
    lib.mapAttrsToList (name: src:
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

  fcChannel = with lib; pkgs.releaseTools.channel {
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
    };
  };

  channels = with lib; pkgs.releaseTools.aggregate {
    name = "channels";
    constituents = channelsUpstream ++ [ fcChannel ];
    meta.description = "only channels, no tests";
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

  mkRelease = { releaseName, constituents ? [ ] }:
    let
      name = "${releaseName}-${version}${versionSuffix}";
      tarOpts = ''
        --owner=0 --group=0 \
        --mtime="1970-01-01 00:00:00 UTC" \
      '';

    in pkgs.releaseTools.channel {
      inherit constituents;
      inherit name;
      src = combinedSources;

      preferLocalBuild = true;

      passthru.src = combinedSources;

      patchPhase = "touch .update-on-nixos-rebuild";
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
in

jobs // {

  inherit channels images doc;

  # Helpful for debugging with nix repl -f release/default.nix but should not included as Hydra jobs.
  # inherit excludedPkgNames overlayPkgNames importantPkgNames overlayPkgNamesToTest importantPkgNamesToTest;

  release = mkRelease {
    releaseName = "release";
    constituents = [
      "channels"
      "doc.roles"
      "images.dev-vm"
      "images.fc"
      "images.netboot"
      "importantPackages.adns.x86_64-linux"
      "importantPackages.apacheHttpd.x86_64-linux"
      "importantPackages.asterisk.x86_64-linux"
      "importantPackages.auditbeat7-oss.x86_64-linux"
      "importantPackages.automake.x86_64-linux"
      "importantPackages.awscli.x86_64-linux"
      "importantPackages.awscli2.x86_64-linux"
      "importantPackages.bash.x86_64-linux"
      "importantPackages.bind.x86_64-linux"
      "importantPackages.binutils.x86_64-linux"
      "importantPackages.bundler.x86_64-linux"
      "importantPackages.cacert.x86_64-linux"
      "importantPackages.calibre.x86_64-linux"
      "importantPackages.ceph.x86_64-linux"
      "importantPackages.chromedriver.x86_64-linux"
      "importantPackages.chromium.x86_64-linux"
      "importantPackages.cifs-utils.x86_64-linux"
      "importantPackages.clamav.x86_64-linux"
      "importantPackages.cmake.x86_64-linux"
      "importantPackages.consul.x86_64-linux"
      "importantPackages.containerd.x86_64-linux"
      "importantPackages.coreutils.x86_64-linux"
      "importantPackages.coturn.x86_64-linux"
      "importantPackages.curl.x86_64-linux"
      "importantPackages.cyrus_sasl.x86_64-linux"
      "importantPackages.db.x86_64-linux"
      "importantPackages.dnsmasq.x86_64-linux"
      "importantPackages.docker-compose.x86_64-linux"
      "importantPackages.docker.x86_64-linux"
      "importantPackages.dovecot.x86_64-linux"
      "importantPackages.element-web.x86_64-linux"
      "importantPackages.erlang.x86_64-linux"
      "importantPackages.exif.x86_64-linux"
      "importantPackages.fetchmail.x86_64-linux"
      "importantPackages.ffmpeg.x86_64-linux"
      "importantPackages.file.x86_64-linux"
      "importantPackages.filebeat7-oss.x86_64-linux"
      "importantPackages.firefox.x86_64-linux"
      "importantPackages.gcc.x86_64-linux"
      "importantPackages.gcc12.x86_64-linux"
      "importantPackages.gd.x86_64-linux"
      "importantPackages.ghostscript.x86_64-linux"
      "importantPackages.git.x86_64-linux"
      "importantPackages.gitaly.x86_64-linux"
      "importantPackages.github-runner.x86_64-linux"
      "importantPackages.gitlab-container-registry.x86_64-linux"
      "importantPackages.gitlab-ee.x86_64-linux"
      "importantPackages.gitlab-pages.x86_64-linux"
      "importantPackages.gitlab-runner.x86_64-linux"
      "importantPackages.gitlab-workhorse.x86_64-linux"
      "importantPackages.gitlab.x86_64-linux"
      "importantPackages.glibc.x86_64-linux"
      "importantPackages.gnumake.x86_64-linux"
      "importantPackages.gnupg.x86_64-linux"
      "importantPackages.go.x86_64-linux"
      "importantPackages.go_1_21.x86_64-linux"
      "importantPackages.go_1_22.x86_64-linux"
      "importantPackages.grafana.x86_64-linux"
      "importantPackages.grub2.x86_64-linux"
      "importantPackages.haproxy.x86_64-linux"
      "importantPackages.imagemagick.x86_64-linux"
      "importantPackages.imagemagick6.x86_64-linux"
      "importantPackages.imagemagick7.x86_64-linux"
      "importantPackages.inetutils.x86_64-linux"
      "importantPackages.jdk.x86_64-linux"
      "importantPackages.jetbrains.jdk.x86_64-linux"
      "importantPackages.jetty.x86_64-linux"
      "importantPackages.jicofo.x86_64-linux"
      "importantPackages.jitsi-meet.x86_64-linux"
      "importantPackages.jitsi-videobridge.x86_64-linux"
      "importantPackages.jq.x86_64-linux"
      "importantPackages.jre.x86_64-linux"
      "importantPackages.k3s.x86_64-linux"
      "importantPackages.k3s_1_27.x86_64-linux"
      "importantPackages.k3s_1_28.x86_64-linux"
      "importantPackages.k3s_1_29.x86_64-linux"
      "importantPackages.k3s_1_30.x86_64-linux"
      "importantPackages.k3s_1_31.x86_64-linux"
      "importantPackages.keycloak.x86_64-linux"
      "importantPackages.kubernetes-helm.x86_64-linux"
      "importantPackages.libffi.x86_64-linux"
      "importantPackages.libgcrypt.x86_64-linux"
      "importantPackages.libjpeg.x86_64-linux"
      "importantPackages.libmodsecurity.x86_64-linux"
      "importantPackages.libmysqlclient.x86_64-linux"
      "importantPackages.libressl.x86_64-linux"
      "importantPackages.libtiff.x86_64-linux"
      "importantPackages.libwebp.x86_64-linux"
      "importantPackages.libxml2.x86_64-linux"
      "importantPackages.libxslt.x86_64-linux"
      "importantPackages.libyaml.x86_64-linux"
      "importantPackages.linuxKernelStable.x86_64-linux"
      "importantPackages.linuxKernelVerify.x86_64-linux"
      "importantPackages.logrotate.x86_64-linux"
      "importantPackages.lz4.x86_64-linux"
      "importantPackages.mailutils.x86_64-linux"
      "importantPackages.mariadb-connector-c.x86_64-linux"
      "importantPackages.mariadb.x86_64-linux"
      "importantPackages.mastodon.x86_64-linux"
      "importantPackages.matomo.x86_64-linux"
      "importantPackages.matomo_5.x86_64-linux"
      "importantPackages.matrix-synapse.x86_64-linux"
      "importantPackages.mcpp.x86_64-linux"
      "importantPackages.memcached.x86_64-linux"
      "importantPackages.mongodb-5_0.x86_64-linux"
      "importantPackages.mongodb-6_0.x86_64-linux"
      "importantPackages.mongodb.x86_64-linux"
      "importantPackages.monitoring-plugins.x86_64-linux"
      "importantPackages.mysql.x86_64-linux"
      "importantPackages.mysql80.x86_64-linux"
      "importantPackages.nfs-utils.x86_64-linux"
      "importantPackages.nginx.x86_64-linux"
      "importantPackages.nginxMainline.x86_64-linux"
      "importantPackages.nginxStable.x86_64-linux"
      "importantPackages.nix.x86_64-linux"
      "importantPackages.nodejs.x86_64-linux"
      "importantPackages.nodejs_18.x86_64-linux"
      "importantPackages.nodejs_20.x86_64-linux"
      "importantPackages.nodejs_22.x86_64-linux"
      "importantPackages.nspr.x86_64-linux"
      "importantPackages.nss_latest.x86_64-linux"
      "importantPackages.openjdk.x86_64-linux"
      "importantPackages.openjpeg.x86_64-linux"
      "importantPackages.openldap.x86_64-linux"
      "importantPackages.openldap_2_4.x86_64-linux"
      "importantPackages.opensearch-dashboards.x86_64-linux"
      "importantPackages.opensearch.x86_64-linux"
      "importantPackages.openssh.x86_64-linux"
      "importantPackages.openssl.x86_64-linux"
      "importantPackages.openssl_1_1.x86_64-linux"
      "importantPackages.openssl_3.x86_64-linux"
      "importantPackages.openvpn.x86_64-linux"
      "importantPackages.pcre.x86_64-linux"
      "importantPackages.pcre2.x86_64-linux"
      "importantPackages.percona-server.x86_64-linux"
      "importantPackages.percona-server_innovation.x86_64-linux"
      "importantPackages.percona-server_lts.x86_64-linux"
      "importantPackages.percona-xtrabackup_8_0.x86_64-linux"
      "importantPackages.percona-xtrabackup_8_3.x86_64-linux"
      "importantPackages.percona-xtrabackup_innovation.x86_64-linux"
      "importantPackages.percona-xtrabackup_lts.x86_64-linux"
      "importantPackages.percona.x86_64-linux"
      "importantPackages.percona57.x86_64-linux"
      "importantPackages.percona80.x86_64-linux"
      "importantPackages.percona83.x86_64-linux"
      "importantPackages.php72.x86_64-linux"
      "importantPackages.php73.x86_64-linux"
      "importantPackages.php74.x86_64-linux"
      "importantPackages.php80.x86_64-linux"
      "importantPackages.php81.x86_64-linux"
      "importantPackages.php82.x86_64-linux"
      "importantPackages.php83.x86_64-linux"
      "importantPackages.phpPackages.composer.x86_64-linux"
      "importantPackages.pkg-config.x86_64-linux"
      "importantPackages.podman.x86_64-linux"
      "importantPackages.poetry.x86_64-linux"
      "importantPackages.polkit.x86_64-linux"
      "importantPackages.postfix.x86_64-linux"
      "importantPackages.postgresqlPackages.postgis.x86_64-linux"
      "importantPackages.postgresql12Packages.postgis.x86_64-linux"
      "importantPackages.postgresql13Packages.postgis.x86_64-linux"
      "importantPackages.postgresql14Packages.postgis.x86_64-linux"
      "importantPackages.postgresql15Packages.postgis.x86_64-linux"
      "importantPackages.postgresql16Packages.postgis.x86_64-linux"
      # "importantPackages.postgresql17Packages.postgis.x86_64-linux"
      "importantPackages.postgresql.x86_64-linux"
      "importantPackages.postgresql_12.x86_64-linux"
      "importantPackages.postgresql_13.x86_64-linux"
      "importantPackages.postgresql_14.x86_64-linux"
      "importantPackages.postgresql_15.x86_64-linux"
      "importantPackages.postgresql_16.x86_64-linux"
      # "importantPackages.postgresql_17.x86_64-linux"
      "importantPackages.powerdns.x86_64-linux"
      "importantPackages.prometheus.x86_64-linux"
      "importantPackages.prosody.x86_64-linux"
      "importantPackages.python3.x86_64-linux"
      "importantPackages.python310.x86_64-linux"
      "importantPackages.python311.x86_64-linux"
      "importantPackages.python312.x86_64-linux"
      "importantPackages.python39.x86_64-linux"
      "importantPackages.python3Packages.boto3.x86_64-linux"
      "importantPackages.python3Packages.click.x86_64-linux"
      "importantPackages.python3Packages.lxml.x86_64-linux"
      "importantPackages.python3Packages.pillow.x86_64-linux"
      "importantPackages.python3Packages.pip.x86_64-linux"
      "importantPackages.python3Packages.pyslurm.x86_64-linux"
      "importantPackages.python3Packages.pystemd.x86_64-linux"
      "importantPackages.python3Packages.pyyaml.x86_64-linux"
      "importantPackages.python3Packages.requests.x86_64-linux"
      "importantPackages.python3Packages.rich-rst.x86_64-linux"
      "importantPackages.python3Packages.rich.x86_64-linux"
      "importantPackages.python3Packages.structlog.x86_64-linux"
      "importantPackages.python3Packages.supervisor.x86_64-linux"
      "importantPackages.python3Packages.systemd.x86_64-linux"
      "importantPackages.python3Packages.urllib3.x86_64-linux"
      "importantPackages.qemu.x86_64-linux"
      "importantPackages.rabbitmq-server.x86_64-linux"
      "importantPackages.rabbitmq-server_3_8.x86_64-linux"
      "importantPackages.rclone.x86_64-linux"
      "importantPackages.re2c.x86_64-linux"
      "importantPackages.redis.x86_64-linux"
      "importantPackages.rich-cli.x86_64-linux"
      "importantPackages.roundcube.x86_64-linux"
      "importantPackages.rsync.x86_64-linux"
      "importantPackages.ruby.x86_64-linux"
      "importantPackages.ruby_3_2.x86_64-linux"
      "importantPackages.runc.x86_64-linux"
      "importantPackages.screen.x86_64-linux"
      "importantPackages.slurm.x86_64-linux"
      "importantPackages.solr.x86_64-linux"
      "importantPackages.strace.x86_64-linux"
      "importantPackages.strongswan.x86_64-linux"
      "importantPackages.subversion.x86_64-linux"
      "importantPackages.sudo.x86_64-linux"
      "importantPackages.sysstat.x86_64-linux"
      "importantPackages.systemd.x86_64-linux"
      "importantPackages.tcpdump.x86_64-linux"
      "importantPackages.telegraf.x86_64-linux"
      "importantPackages.tmux.x86_64-linux"
      "importantPackages.tomcat10.x86_64-linux"
      "importantPackages.tomcat9.x86_64-linux"
      "importantPackages.unifi.x86_64-linux"
      "importantPackages.unzip.x86_64-linux"
      "importantPackages.util-linux.x86_64-linux"
      "importantPackages.varnish.x86_64-linux"
      "importantPackages.vim.x86_64-linux"
      "importantPackages.webkitgtk.x86_64-linux"
      "importantPackages.wget.x86_64-linux"
      "importantPackages.wireguard-tools.x86_64-linux"
      "importantPackages.xfsprogs.x86_64-linux"
      "importantPackages.xorg.libX11.x86_64-linux"
      "importantPackages.xz.x86_64-linux"
      "importantPackages.zip.x86_64-linux"
      "importantPackages.zlib.x86_64-linux"
      "importantPackages.zoneminder.x86_64-linux"
      "importantPackages.zsh.x86_64-linux"
      "importantPackages.zstd.x86_64-linux"
      "pkgs.apacheHttpdLegacyCrypt.x86_64-linux"
      "pkgs.auditbeat7-oss.x86_64-linux"
      "pkgs.auditbeat7.x86_64-linux"
      "pkgs.boost159.x86_64-linux"
      "pkgs.busybox.x86_64-linux"
      "pkgs.certmgr.x86_64-linux"
      "pkgs.check_ipmi_sensor.x86_64-linux"
      "pkgs.check_md_raid.x86_64-linux"
      "pkgs.check_megaraid.x86_64-linux"
      "pkgs.cyrus_sasl-legacyCrypt.x86_64-linux"
      "pkgs.docker.x86_64-linux"
      "pkgs.docsplit.x86_64-linux"
      "pkgs.dovecot.x86_64-linux"
      "pkgs.fc.agent.x86_64-linux"
      "pkgs.fc.agentWithSlurm.x86_64-linux"
      "pkgs.fc.blockdev.x86_64-linux"
      "pkgs.fc.check-age.x86_64-linux"
      "pkgs.fc.check-haproxy.x86_64-linux"
      "pkgs.fc.check-journal.x86_64-linux"
      "pkgs.fc.check-mongodb.x86_64-linux"
      "pkgs.fc.check-postfix.x86_64-linux"
      "pkgs.fc.check-xfs-broken.x86_64-linux"
      "pkgs.fc.fix-so-rpath.x86_64-linux"
      "pkgs.fc.logcheckhelper.x86_64-linux"
      "pkgs.fc.multiping.x86_64-linux"
      "pkgs.fc.roundcube-chpasswd-py.x86_64-linux"
      "pkgs.fc.roundcube-chpasswd.x86_64-linux"
      "pkgs.fc.secure-erase.x86_64-linux"
      "pkgs.fc.sensuplugins.x86_64-linux"
      "pkgs.fc.sensusyntax.x86_64-linux"
      "pkgs.fc.telegraf-collect-psi.x86_64-linux"
      "pkgs.fc.userscan.x86_64-linux"
      "pkgs.filebeat7-oss.x86_64-linux"
      "pkgs.filebeat7.x86_64-linux"
      "pkgs.innotop.x86_64-linux"
      "pkgs.kubernetes-dashboard-metrics-scraper.x86_64-linux"
      "pkgs.kubernetes-dashboard.x86_64-linux"
      "pkgs.lamp_php72.x86_64-linux"
      "pkgs.lamp_php73.x86_64-linux"
      "pkgs.lamp_php74.x86_64-linux"
      "pkgs.lamp_php80.x86_64-linux"
      "pkgs.lamp_php81.x86_64-linux"
      "pkgs.lamp_php82.x86_64-linux"
      "pkgs.lamp_php83.x86_64-linux"
      "pkgs.latencytop_nox.x86_64-linux"
      "pkgs.libmodsecurity.x86_64-linux"
      "pkgs.libxcrypt-with-sha256.x86_64-linux"
      "pkgs.links2_nox.x86_64-linux"
      "pkgs.linuxKernelStable.x86_64-linux"
      "pkgs.linuxKernelVerify.x86_64-linux"
      "pkgs.lkl.x86_64-linux"
      "pkgs.matomo-beta.x86_64-linux"
      "pkgs.matomo.x86_64-linux"
      "pkgs.monitoring-plugins.x86_64-linux"
      "pkgs.mysql.x86_64-linux"
      "pkgs.nginx.x86_64-linux"
      "pkgs.nginxLegacyCrypt.x86_64-linux"
      "pkgs.nginxMainline.x86_64-linux"
      "pkgs.nginxStable.x86_64-linux"
      "pkgs.openldap_2_4.x86_64-linux"
      "pkgs.opensearch-dashboards.x86_64-linux"
      "pkgs.percona-toolkit.x86_64-linux"
      "pkgs.percona-xtrabackup_2_4.x86_64-linux"
      "pkgs.percona-xtrabackup_8_3.x86_64-linux"
      "pkgs.percona-xtrabackup_8_4.x86_64-linux"
      "pkgs.percona.x86_64-linux"
      "pkgs.percona57.x86_64-linux"
      "pkgs.percona80.x86_64-linux"
      "pkgs.percona83.x86_64-linux"
      "pkgs.percona84.x86_64-linux"
      "pkgs.php72.x86_64-linux"
      "pkgs.php73.x86_64-linux"
      "pkgs.php74.x86_64-linux"
      "pkgs.php80.x86_64-linux"
      "pkgs.php81.x86_64-linux"
      "pkgs.php82.x86_64-linux"
      "pkgs.php83.x86_64-linux"
      "pkgs.pkgconfig.x86_64-linux"
      "pkgs.postfix.x86_64-linux"
      "pkgs.prometheus-elasticsearch-exporter.x86_64-linux"
      "pkgs.pypolicyd-spf.x86_64-linux"
      "pkgs.python27.x86_64-linux"
      "pkgs.rabbitmq-server_3_8.x86_64-linux"
      "pkgs.rich-cli.x86_64-linux"
      "pkgs.solr.x86_64-linux"
      "pkgs.temporal_tables.x86_64-linux"
      "pkgs.xtrabackup.x86_64-linux"
      "tests.antivirus"
      "tests.audit"
      "tests.collect-garbage"
      "tests.coturn"
      "tests.devhost"
      "tests.docker"
      "tests.fcagent"
      "tests.ferretdb"
      "tests.ffmpeg"
      "tests.filebeat"
      "tests.gitlab"
      "tests.haproxy"
      "tests.java"
      "tests.journal"
      "tests.journalbeat"
      "tests.k3s"
      "tests.k3s_monitoring"
      "tests.kernelconfig"
      "tests.kernelversions"
      "tests.lampPackage74"
      "tests.lampPackage80"
      "tests.lampPackage81"
      "tests.lampPackage82"
      "tests.lampPackage83"
      "tests.lampVm"
      "tests.lampVm72"
      "tests.lampVm73"
      "tests.lampVm74"
      "tests.lampVm80"
      "tests.lampVm81"
      "tests.lampVm82"
      "tests.lampVm83"
      "tests.locale"
      "tests.login"
      "tests.logrotate"
      "tests.mail"
      "tests.mailstub"
      "tests.matomo"
      "tests.memcached"
      "tests.mongodb32"
      "tests.mongodb34"
      "tests.mongodb36"
      "tests.mongodb40"
      "tests.mongodb42"
      "tests.mysql57"
      "tests.network.firewall"
      "tests.network.loopback"
      "tests.network.name-resolution"
      "tests.network.ping-vlans"
      "tests.network.routes"
      "tests.network.wireguard"
      "tests.nfs"
      "tests.nginx"
      "tests.nodejs"
      "tests.opensearch"
      "tests.opensearch_dashboards"
      "tests.openvpn"
      "tests.percona80"
      "tests.percona83"
      # "tests.percona84"
      "tests.physical-installer"
      "tests.postgresql-autoupgrade.automatic"
      "tests.postgresql-autoupgrade.manual"
      "tests.postgresql12"
      "tests.postgresql13"
      "tests.postgresql14"
      "tests.postgresql15"
      "tests.postgresql16"
      # "tests.postgresql17"
      "tests.prometheus"
      "tests.rabbitmq"
      "tests.redis"
      "tests.rg-relay"
      "tests.sensuclient"
      "tests.servicecheck"
      "tests.statshost-global"
      "tests.statshost-master"
      "tests.sudo"
      "tests.syslog.extraRules"
      "tests.syslog.plain"
      "tests.syslog.separateFacilities"
      "tests.systemd-service-cycles"
      "tests.users"
      "tests.vxlan"
      "tests.webproxy"
    ];
  };

  releaseUntested = mkRelease {
      releaseName = "releaseUntested";
  };

  releaseSmall = mkRelease {
    releaseName = "releaseSmall";
    constituents = [
      "channels"
      "tests.audit"
      "tests.collect-garbage"
      "tests.fcagent"
      "tests.filebeat"
      "tests.kernelconfig"
      "tests.locale"
      "tests.login"
      "tests.logrotate"
      "tests.sensuclient"
      "tests.sudo"
      "tests.syslog.plain"
      "tests.systemd-service-cycles"
      "tests.users"
      "tests.network.firewall"
      "tests.network.loopback"
      "tests.network.name-resolution"
      "tests.network.ping-vlans"
    ];
  };

}
