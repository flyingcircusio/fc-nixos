.. _nixos-base:

Base environment
================

The base installation includes various tools that generally help with
application deployment. They are available on every Flying Circus NixOS VM.
The package's installation includes availability to run them manually and
to compile your own software against them.

However, those are intended for short-term convenience. Linking against them
may cause breakage of your applications in the long term.

Also, those packages are not providing running daemons (like OpenLDAP). If you
need a managed component, those need to be activated explicitly.

Packages
--------

* apacheHttpd
* atop
* automake
* bc
* bundler
* cmake
* cups
* curl
* cyrus_sasl
* db
* dnsutils
* dstat
* file
* fc.logcheckhelper
* fio
* gcc
* gdb
* git
* gnumake
* gnupg
* gptfdisk
* graphviz
* htop
* imagemagick
* iotop
* jq
* libjpeg
* libtiff
* libxml2
* libxslt
* links
* lsof
* lynx
* mailx
* mercurial
* mmv
* nano
* ncdu
* netcat
* netcat
* ngrep
* nmap
* nodejs
* openldap
* openssl
* php
* pkgconfig
* protobuf
* psmisc
* pwgen
* python2Full
* python3
* pythonPackages.virtualenv
* ripgrep
* screen
* strace
* sysstat
* tcpdump
* telnet
* tree
* unzip
* vim
* vulnix
* wdiff
* wget
* xfsprogs

Configuration
-------------

All tools can be configured individually with dotfiles in the user's home
directory.


Interaction
-----------

Service users may invoke :command:`sudo systemctl` to restart individual
services manually. See also :ref:`nixos-local` for information about how to
activate configuration changes.


.. vim: set spell spelllang=en:
