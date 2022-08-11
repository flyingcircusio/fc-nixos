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
        inetutils
        multipath-tools  # kpartx
        iotop
        jq
        latencytop
        libjpeg
        libsmbios
        libtiff
        libxml2
        libxslt
        links2
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
        openldap
        openssl
        parted
        pkg-config
        protobuf
        w3m-nographics
        psmisc
        pwgen
        python2Full
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
        usbutils
        vim
        wdiff
        wget
        xfsprogs
        zip
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${pkgs.iotop}/bin/iotop" ];
        groups = [ "sudo-srv" "service" ];
      }
    ];

  };
}
