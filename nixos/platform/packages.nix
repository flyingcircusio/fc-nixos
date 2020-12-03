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
        tmux
        tree
        unzip
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
