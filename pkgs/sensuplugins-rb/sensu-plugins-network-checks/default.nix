{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-network-checks";
  exes = [ 
    "check-netstat-tcp.rb"
    "check-ports.rb"
  ];
}
