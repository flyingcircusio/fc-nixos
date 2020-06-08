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
        iotop
        jq
        libjpeg
        libtiff
        libxml2
        libxslt
        links
        lsof
        lynx
        magic-wormhole
        mailx
        mercurial
        mmv
        nano
        ncdu
        netcat
        netcat
        ngrep
        nmap
        nodejs
        openldap
        openssl
        php
        pkgconfig
        protobuf
        psmisc
        pwgen
        python2Full
        python3
        pythonPackages.virtualenv
        ripgrep
        screen
        strace
        sysstat
        tcpdump
        telnet
        tree
        unzip
        vim
        wdiff
        wget
        xfsprogs
    ] ++
    lib.optional (!config.services.postgresql.enable) pkgs.postgresql;

    flyingcircus.passwordlessSudoRules = [
      { 
        commands = [ "${pkgs.iotop}/bin/iotop" ];
        groups = [ "sudo-srv" "service" ];
      }
    ];

  };
}
