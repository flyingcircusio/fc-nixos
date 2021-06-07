{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-disk-checks";
  exes = [
    "check-disk-usage.rb"
    "check-fstab-mounts.rb"
    "check-smart.rb"
    "check-smart-status.rb"
    "check-smart-tests.rb"
    "metrics-disk-capacity.rb"
    "metrics-disk.rb"
    "metrics-disk-usage.rb"
  ];
}
