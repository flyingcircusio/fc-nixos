{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-elasticsearch";
  exes = [
    "check-es-circuit-breakers.rb"
    "check-es-cluster-health.rb"
    "check-es-file-descriptors.rb"
    "check-es-heap.rb"
    "check-es-node-status.rb"
    "check-es-shard-allocation-status.rb"
  ];
}
