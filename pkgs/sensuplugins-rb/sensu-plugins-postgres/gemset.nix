{
  dentaku = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "18ga010bbhsgc876vf6z6swfnk2mgj30y96rcd4yafvmwnj5djgz";
      type = "gem";
    };
    version = "2.0.4";
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
  pg = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "00g33hdixgync6gp4mn0g0kjz5qygshi47xw58kdpd9n5lzdpg8c";
      type = "gem";
    };
    version = "0.18.3";
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
  sensu-plugins-postgres = {
    dependencies = ["dentaku" "pg" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0sk1sqqs6c3wdc7cl3pqrb5pfbaqn88fjyik0bvhli8c8wds0h1v";
      type = "gem";
    };
    version = "2.3.2";
  };
}
