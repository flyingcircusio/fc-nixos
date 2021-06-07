{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-influxdb";
  exes = [
    "check-influxdb-query.rb"
    "check-influxdb.rb"
    "metrics-influxdb.rb"
    "mutator-influxdb-line-protocol.rb"
  ];
}
