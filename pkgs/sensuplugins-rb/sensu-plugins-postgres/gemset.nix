{
  dentaku = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1976bjf4ag2wx6bv8r56zzd4bnkimy2a5c2iya9x39sk58v17d10";
      type = "gem";
    };
    version = "3.3.4";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0nalhin1gda4v8ybk6lq8f407cgfrj6qzn234yra4ipkmlbfmal6";
      type = "gem";
    };
    version = "2.6.3";
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
      sha256 = "13mfrysrdrh8cka1d96zm0lnfs59i5x2g6ps49r2kz5p3q81xrzj";
      type = "gem";
    };
    version = "1.2.3";
  };
  sensu-plugin = {
    dependencies = ["json" "mixlib-cli"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1hibm8q4dl5bp949h21zjc3d2ss26mg4sl5svy7gl7bz59k9dg06";
      type = "gem";
    };
    version = "4.0.0";
  };
  sensu-plugins-postgres = {
    dependencies = ["dentaku" "pg" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0b9jac86fj56qbi0y0r3a8wfpkskalzijbfpndj3w4r4ds9gxjpf";
      type = "gem";
    };
    version = "4.2.0";
  };
}
