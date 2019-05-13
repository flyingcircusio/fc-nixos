{ bundlerSensuPlugin, postgresql }:

bundlerSensuPlugin {
  pname = "sensu-plugins-postgres";
  exes = [ "check-postgres-alive.rb" ];

  extraGemConfig = {
    sensu-plugins-postgres = attrs: {
      buildInputs = [ postgresql ];
    };
  };
}
