{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-memcached";
  exes = [ "check-memcached-stats.rb" ];
}
