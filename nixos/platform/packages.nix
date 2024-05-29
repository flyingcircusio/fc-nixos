{ config, pkgs, lib, ... }:

{
  config = {

    environment.systemPackages = with pkgs; [
        apacheHttpd
        atop
        automake
        bc
        cmake
        curl
        db
        dnsutils
        dstat
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
        multipath-tools  # kpartx
        iotop
        jq
        latencytop_nox
        links2_nox
        lsof
        lnav
        lynx
        magic-wormhole
        mailutils
        mercurial
        mmv
        nano
        ncdu
        netcat
        ngrep
        nix-top
        nixfmt-rfc-style
        nmap
        nvd
        openssl
        parted
        pkg-config
        w3m-nographics
        psmisc
        pwgen
        (python3.withPackages (ps: with ps; [ setuptools ]))
        python3Packages.virtualenv
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
        wdiff
        wget
        xfsprogs
        zip
    ];

    programs.mtr.enable = config.fclib.mkPlatform true;

    flyingcircus.passwordlessSudoPackages = [
      {
        commands = [ "bin/iotop" ];
        package = pkgs.iotop;
        groups = [ "admins" "sudo-srv" "service" ];
      }
    ];

  };
}
