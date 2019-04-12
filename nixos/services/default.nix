{
  imports = [
    ./collectdproxy.nix
    ./haproxy.nix
    ./logrotate
    ./nginx
    ./sensu.nix
    ./syslog.nix
    ./telegraf.nix
  ];
}
