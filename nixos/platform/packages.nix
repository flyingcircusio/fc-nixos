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
        file
        fc.logcheckhelper
        fio
        gcc
        gdb
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
        lynx
        magic-wormhole
        mailutils
        mercurial
        mmv
        nano
        ncdu
        netcat
        ngrep
        nmap
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

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${pkgs.iotop}/bin/iotop" ];
        groups = [ "admins" "sudo-srv" "service" ];
      }
    ];

  };
}
