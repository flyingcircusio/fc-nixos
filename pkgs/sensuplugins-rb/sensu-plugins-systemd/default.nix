{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-systemd";
  exes = [ "check-failed-units.rb" ];
}
