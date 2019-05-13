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
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0abdlwb64ns7ssmiqhdwgl27ly40x2l27l8hs8hn0z4kb3zd2x3v";
      type = "gem";
    };
    version = "0.5.20180417";
  };
  http-cookie = {
    dependencies = ["domain_name"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "004cgs4xg5n6byjs7qld0xhsjq3n6ydfh897myr2mibvh6fjc49g";
      type = "gem";
    };
    version = "1.0.3";
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
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0sx97bm9by389rbzv8r1f43h06xcz8vwi3h5jv074gvparql7lcx";
      type = "gem";
    };
    version = "2.2.0";
  };
  mime-types = {
    dependencies = ["mime-types-data"];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0fjxy1jm52ixpnv3vg9ld9pr9f35gy0jp66i1njhqjvmnvq0iwwk";
      type = "gem";
    };
    version = "3.2.2";
  };
  mime-types-data = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1m00pg19cm47n1qlcxgl91ajh2yq0fszvn1vy8fy0s1jkrp9fw4a";
      type = "gem";
    };
    version = "3.2019.0331";
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
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "057c631lrq3xcf7sgx3z52cybfhp4k4k0vicqhkrpx0whi6brwid";
      type = "gem";
    };
    version = "8.0.0";
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
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1ll6w64ibh81qwvjx19h8nj7mngxgffg7aigjx11klvf5k2g4nxf";
      type = "gem";
    };
    version = "0.0.7.6";
  };
}