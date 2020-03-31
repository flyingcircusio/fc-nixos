{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-kubernetes";
  exes = [
    "check-kube-nodes-ready.rb"
    "check-kube-apiserver-available.rb"
    "check-kube-pods-pending.rb"
    "check-kube-service-available.rb"
    "check-kube-pods-runtime.rb"
    "check-kube-pods-running.rb"
    "check-kube-pods-restarting.rb"
  ];

  extraGemConfig = {
    sensu-plugins-kubernetes = attrs: {
      buildInputs = [  ];
    };
  };
}
