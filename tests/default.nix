{ pkgs, lib, supportedSystems, ... }:

{
  memcached = import ./memcached.nix {};
}
