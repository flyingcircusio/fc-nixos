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
        mercurial
        mmv
        nano
        netcat
        ncdu
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
        vulnix
        wget
        xfsprogs
    ] ++
    lib.optional (!config.services.postgresql.enable) pkgs.postgresql;

    security.sudo.extraRules = [
      { groups = [ "sudo-srv" "service" ];
        commands = [ "${pkgs.iotop}/bin/iotop" ];
      }
    ];

  };
}
