{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-entropy-checks";
  exes = [ "check-entropy.rb" ];
}
