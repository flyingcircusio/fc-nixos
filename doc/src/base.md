(nixos-base)=

# Base environment

The base installation includes various packages that generally help with
application deployment and provide various system tools. Most of them add
executable files to the global PATH and some can be used as a library.

Depending on globally-installed packages should generally be avoided as this
may cause breakage of your applications, especially on NixOS upgrades. It's
better to use custom user environments to install application dependencies,
as described in {ref}`nixos-user-package-management` or other methods to
isolate application dependencies from the system.

Also note that these packages don't provide running services/daemons, like
`apacheHttpd`. Services are typically activated by adding _roles_
(also called _components_) to a machine, for example `lamp`.

You can look up packages and their descriptions via the [NixOS Package Search](https://search.nixos.org/packages).

## Packages added by our platform

- apacheHttpd
- atop
- automake
- bc
- cmake
- curl
- db
- dnsutils
- dstat
- ethtool
- file
- fc.logcheckhelper
- fio
- gcc
- gdb
- git
- gnumake
- gnupg
- gptfdisk
- htop
- inetutils (telnet)
- iotop
- jq
- latencytop
- links2
- lsof
- lynx
- mailx
- mercurial
- mmv
- mtr
- nano
- ncdu
- netcat
- ngrep
- nix-top
- nixfmt
- nmap
- nvd
- openssl
- pkg-config
- psmisc
- pwgen
- python3
- pythonPackages.virtualenv
- ripgrep
- screen
- statix
- strace
- sysstat
- tcpdump
- tree
- unzip
- vim
- w3m-nographics
- wdiff
- wget
- xfsprogs

## Configuration

We provide global basic config for some tools, like bash. Further
configuration can be done with _dotfiles_ in a user's home directory.


% vim: set spell spelllang=en:
