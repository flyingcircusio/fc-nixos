{
  imports = [
    ./collectdproxy.nix
    ./haproxy.nix
    ./logrotate
    ./nginx
    ./sensu.nix
    ./telegraf.nix
  ];
}
