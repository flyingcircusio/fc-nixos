{ config, pkgs, lib, ... }:

{
  config = {

    environment.systemPackages = with pkgs; [
        apacheHttpd
        atop
        automake
        bc
        bundler
        cmake
        cups
        curl
        cyrus_sasl
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
        graphviz
        htop
        imagemagick
        multipath_tools  # kpartx
        iotop
        jq
        latencytop
        libjpeg
        libsmbios
        libtiff
        libxml2
        libxslt
        links
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
        nodejs
        openldap
        openssl
        parted
        pkgconfig
        protobuf
        w3m-nographics
        psmisc
        pwgen
        python2Full
        python3
        python3Packages.virtualenv
        ripgrep
        screen
        strace
        sysstat
        tcpdump
        telnet
        tmux
        tree
        unzip
        usbutils
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
