(nixos-base)=

# Base environment

The base installation includes various tools that generally help with
application deployment. They are available on every Flying Circus NixOS VM.
The package's installation includes availability to run them manually and
to compile your own software against them.

However, those are intended for short-term convenience. Linking against them
may cause breakage of your applications in the long term.

Also, those packages are not providing running daemons (like apacheHttpd). If you
need a managed component, those need to be activated explicitly.

You can look up packages and their descriptions via the [NixOS Package Search](https://search.nixos.org/packages).

## Packages

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

All tools can be configured individually with dotfiles in the user's home
directory.

## Interaction

Service users may invoke {command}`sudo systemctl` to restart individual
services manually. See also {ref}`nixos-local` for information about how to
activate configuration changes.

% vim: set spell spelllang=en:
