{
  json = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0qmj7fypgb9vag723w1a49qihxrcf5shzars106ynw2zk352gbv5";
      type = "gem";
    };
    version = "1.8.6";
  };
  mixlib-cli = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0647msh7kp7lzyf6m72g6snpirvhimjm22qb8xgv9pdhbcrmcccp";
      type = "gem";
    };
    version = "1.7.0";
  };
  sensu-plugin = {
    dependencies = ["json" "mixlib-cli"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1x4zka4zia2wk3gp0sr4m4lzsf0m7s4a3gcgs936n2mgzsbcaa86";
      type = "gem";
    };
    version = "1.4.7";
  };
  sensu-plugins-postfix = {
    dependencies = ["sensu-plugin"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1fsbw0aq5ilhrjnj7jr4r3id5aja6nimvdshxrwg2bnpsqsczaqq";
      type = "gem";
    };
    version = "1.0.0";
  };
}