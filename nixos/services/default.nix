{ ... }:
{
  imports = [
    ./logrotate
    ./sensu.nix
    ./telegraf.nix
  ];
}
