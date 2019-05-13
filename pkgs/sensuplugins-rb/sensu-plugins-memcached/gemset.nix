{
  dalli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0zr66q3ndc0yd17hxll8y0j1j33y4kxw5cgjpvfpdc27wflcxx4i";
      type = "gem";
    };
    version = "2.7.10";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
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
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1x4zka4zia2wk3gp0sr4m4lzsf0m7s4a3gcgs936n2mgzsbcaa86";
      type = "gem";
    };
    version = "1.4.7";
  };
  sensu-plugins-memcached = {
    dependencies = ["dalli" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1wlqlv2gpgapd4lfbyxlk09qw9jypbcg8ankjfds7z1rx6p7cxq5";
      type = "gem";
    };
    version = "0.1.3";
  };
}