{
  config,
  pkgs,
  lib,
  ...
}:

{
  config = {

    environment.systemPackages =
      with pkgs;
      let
        previousPythonVersion =
          ver: "${lib.versions.major ver}${toString (lib.toInt (lib.versions.minor ver) - 1)}";
        previousPython = pkgs."python${previousPythonVersion pkgs.python3.version}";
      in
      [
        apacheHttpd
        automake
        bc
        cmake
        curl
        db
        dnsutils
        dool
        ethtool
        fd
        file
        fc.logcheckhelper
        fio
        gcc
        git
        gnumake
        gnupg
        gptfdisk
        htop
        inetutils
        multipath-tools # kpartx
        iotop
        jq
        links2_nox
        lsof
        lnav
        lynx
        magic-wormhole
        mercurial
        mmv
        nano
        ncdu
        netcat
        ngrep
        nix-top
        nixfmt
        nmap
        nvd
        openssl
        parted
        pkg-config
        psmisc
        pwgen
        (python3.withPackages (ps: with ps; [ setuptools ]))
        # keep around at least one previous python version for upgrade compatibility
        (previousPython.withPackages (ps: with ps; [ setuptools ]))
        python3Packages.virtualenv
        rclone
        ripgrep
        screen
        statix
        strace
        sysstat
        tcpdump
        tmux
        tree
        unzip
        vim
        w3m-nographics
        wdiff
        wget
        xfsprogs
        zip
      ];

    programs.git = {
      enable = true;
      lfs.enable = true;
    };

    environment.shellAliases = {
      dstat = "dool";
    };

    programs.mtr.enable = config.fclib.mkPlatform true;

    flyingcircus.passwordlessSudoPackages = [
      {
        commands = [ "bin/iotop" ];
        package = pkgs.iotop;
        groups = [
          "admins"
          "sudo-srv"
          "service"
        ];
      }
    ];

  };
}
