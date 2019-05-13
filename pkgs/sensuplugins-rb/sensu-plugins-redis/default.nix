{ bundlerSensuPlugin, redis }:

bundlerSensuPlugin {
  pname = "sensu-plugins-redis";
  exes = [ "check-redis-ping.rb" ];

  extraGemConfig = {
    sensu-plugins-redis = attrs: {
      buildInputs = [ redis ];
    };
  };
}
