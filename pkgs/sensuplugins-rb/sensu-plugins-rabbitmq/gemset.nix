{
  amq-protocol = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1rpn9vgh7y037aqhhp04smihzr73vp5i5g6xlqlha10wy3q0wp7x";
      type = "gem";
    };
    version = "2.0.1";
  };
  bunny = {
    dependencies = ["amq-protocol"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "01036bz08dw6l9d3cpd1zp8h4x13lb7rih3n2flcvy0ak2laz7vr";
      type = "gem";
    };
    version = "2.6.4";
  };
  carrot-top = {
    dependencies = ["json"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0bj8290f3h671qf7sdc2vga0iis86mvcsvamdi9nynmh9gmfis5w";
      type = "gem";
    };
    version = "0.0.7";
  };
  domain_name = {
    dependencies = ["unf"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lcqjsmixjp52bnlgzh4lg9ppsk52x9hpwdjd53k8jnbah2602h0";
      type = "gem";
    };
    version = "0.5.20190701";
  };
  http-cookie = {
    dependencies = ["domain_name"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "13rilvlv8kwbzqfb644qp6hrbsj82cbqmnzcvqip1p6vqx36sxbk";
      type = "gem";
    };
    version = "1.0.5";
  };
  inifile = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1c5zmk7ia63yw5l2k14qhfdydxwi1sah1ppjdiicr4zcalvfn0xi";
      type = "gem";
    };
    version = "3.0.0";
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
  mime-types = {
    dependencies = ["mime-types-data"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0ipw892jbksbxxcrlx9g5ljq60qx47pm24ywgfbyjskbcl78pkvb";
      type = "gem";
    };
    version = "3.4.1";
  };
  mime-types-data = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1pky3vzaxlgm9gw5wlqwwi7wsw3jrglrfflrppvvnsrlaiz043z9";
      type = "gem";
    };
    version = "3.2023.0218.1";
  };
  mixlib-cli = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0647msh7kp7lzyf6m72g6snpirvhimjm22qb8xgv9pdhbcrmcccp";
      type = "gem";
    };
    version = "1.7.0";
  };
  netrc = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0gzfmcywp1da8nzfqsql2zqi648mfnx6qwkig3cv36n9m0yy676y";
      type = "gem";
    };
    version = "0.11.0";
  };
  rest-client = {
    dependencies = ["http-cookie" "mime-types" "netrc"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1hzcs2r7b5bjkf2x2z3n8z6082maz0j8vqjiciwgg3hzb63f958j";
      type = "gem";
    };
    version = "2.0.2";
  };
  ruby_dig = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1qcpmf5dsmzxda21wi4hv7rcjjq4x1vsmjj20zpbj5qg2k26hmp9";
      type = "gem";
    };
    version = "0.0.2";
  };
  sensu-plugin = {
    dependencies = ["json" "mixlib-cli"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1hibm8q4dl5bp949h21zjc3d2ss26mg4sl5svy7gl7bz59k9dg06";
      type = "gem";
    };
    version = "4.0.0";
  };
  sensu-plugins-rabbitmq = {
    dependencies = ["amq-protocol" "bunny" "carrot-top" "inifile" "rest-client" "ruby_dig" "sensu-plugin" "stomp"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1fnvfp2pp72igs3cr1na4qwwv1isisriyiphwwwj5nzmjkp03437";
      type = "gem";
    };
    version = "8.1.0";
  };
  stomp = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1ffkaq7dyh18msvv3x89vdbkn7cjfjc3i1y6qyj393dyp78n7pwd";
      type = "gem";
    };
    version = "1.4.7";
  };
  unf = {
    dependencies = ["unf_ext"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0bh2cf73i2ffh4fcpdn9ir4mhq8zi50ik0zqa1braahzadx536a9";
      type = "gem";
    };
    version = "0.1.4";
  };
  unf_ext = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1yj2nz2l101vr1x9w2k83a0fag1xgnmjwp8w8rw4ik2rwcz65fch";
      type = "gem";
    };
    version = "0.0.8.2";
  };
}
