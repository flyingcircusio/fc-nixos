{ bundlerSensuPlugin, mysql }:

bundlerSensuPlugin {
  pname = "sensu-plugins-mysql";
  exes = [ "check-mysql-alive.rb" ];

  extraGemConfig = {
    sensu-plugins-mysql = attrs: {
      buildInputs = [ mysql ];
    };
  };
}
