{
  addressable = {
    dependencies = ["public_suffix"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "15s8van7r2ad3dq6i03l3z4hqnvxcq75a3h72kxvf9an53sqma20";
      type = "gem";
    };
    version = "2.8.4";
  };
  amq-protocol = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1rpn9vgh7y037aqhhp04smihzr73vp5i5g6xlqlha10wy3q0wp7x";
      type = "gem";
    };
    version = "2.0.1";
  };
  amqp = {
    dependencies = ["amq-protocol" "eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0kbrqnpjgj9v0722p3n5rw589l4g26ry8mcghwc5yr20ggkpdaz9";
      type = "gem";
    };
    version = "1.6.0";
  };
  childprocess = {
    dependencies = ["ffi"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1lv7axi1fhascm9njxh3lx1rbrnsm8wgvib0g7j26v4h1fcphqg0";
      type = "gem";
    };
    version = "0.5.8";
  };
  cookiejar = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0q0kmbks9l3hl0wdq744hzy97ssq9dvlzywyqv9k9y1p3qc9va2a";
      type = "gem";
    };
    version = "0.3.3";
  };
  em-http-request = {
    dependencies = ["addressable" "cookiejar" "em-socksify" "eventmachine" "http_parser.rb"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "13rxmbi0fv91n4sg300v3i9iiwd0jxv0i6xd0sp81dx3jlx7kasx";
      type = "gem";
    };
    version = "1.1.5";
  };
  em-http-server = {
    dependencies = ["eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0y8l4gymy9dzjjchjav90ck6has2i2zdjihlhcyrg3jgq6kjzyq5";
      type = "gem";
    };
    version = "0.1.8";
  };
  em-socksify = {
    dependencies = ["eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0rk43ywaanfrd8180d98287xv2pxyl7llj291cwy87g1s735d5nk";
      type = "gem";
    };
    version = "0.3.2";
  };
  em-worker = {
    dependencies = ["eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0z4jx9z2q5hxvdvik4yp0ahwfk69qsmdnyp72ln22p3qlkq2z5wk";
      type = "gem";
    };
    version = "0.0.2";
  };
  eventmachine = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0wh9aqb0skz80fhfn66lbpr4f86ya2z5rx6gm5xlfhd05bj1ch4r";
      type = "gem";
    };
    version = "1.2.7";
  };
  ffi = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0c2dl10pi6a30kcvx2s6p2v1wb4kbm48iv38kmz2ff600nirhpb8";
      type = "gem";
    };
    version = "1.9.21";
  };
  "http_parser.rb" = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1gj4fmls0mf52dlr928gaq0c0cb0m3aqa9kaa6l0ikl2zbqk42as";
      type = "gem";
    };
    version = "0.8.0";
  };
  oj = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "147whmq8h2n04chskl3v4a132xhz5i6kk6vhnz83jwng4vihin5f";
      type = "gem";
    };
    version = "2.18.1";
  };
  parse-cron = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "02fj9i21brm88nb91ikxwxbwv9y7mb7jsz6yydh82rifwq7357hg";
      type = "gem";
    };
    version = "0.1.4";
  };
  public_suffix = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0hz0bx2qs2pwb0bwazzsah03ilpf3aai8b7lk7s35jsfzwbkjq35";
      type = "gem";
    };
    version = "5.0.1";
  };
  sensu = {
    dependencies = ["em-http-request" "em-http-server" "eventmachine" "parse-cron" "sensu-extension" "sensu-extensions" "sensu-json" "sensu-logger" "sensu-redis" "sensu-settings" "sensu-spawn" "sensu-transport"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1pks6wij3drk05wwdfccwlndaj9q1bnn30ra2b6magwi34mixbw7";
      type = "gem";
    };
    version = "1.9.0";
  };
  sensu-extension = {
    dependencies = ["eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0bpizp4n01rv72cryjjlrbfxxj3csish3mkxjzdy4inpi5j5h1dw";
      type = "gem";
    };
    version = "1.5.2";
  };
  sensu-extensions = {
    dependencies = ["sensu-extension" "sensu-extensions-check-dependencies" "sensu-extensions-debug" "sensu-extensions-deregistration" "sensu-extensions-json" "sensu-extensions-occurrences" "sensu-extensions-only-check-output" "sensu-extensions-ruby-hash" "sensu-json" "sensu-logger" "sensu-settings"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1313g6x3qwldk44p3v46sm3w1hz0pc89nslcwdw3v2j78a99a62y";
      type = "gem";
    };
    version = "1.11.0";
  };
  sensu-extensions-check-dependencies = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1hc4kz7k983f6fk27ikg5drvxm4a85qf1k07hqssfyk3k75jyj1r";
      type = "gem";
    };
    version = "1.1.0";
  };
  sensu-extensions-debug = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "11abdgn2kkkbvxq4692yg6a27qnxz4349gfiq7d35biy7vrw34lp";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-extensions-deregistration = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1rarsd7vjflvzgs3hm6z3ypfp3rbzq2723wc0rqxnkpahzdrwr6c";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-extensions-json = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1wnbn9sycdqdh9m0fhszaqkv0jijs3fkdbvcv8kdspx6irbv3m6g";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-extensions-occurrences = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lx5wsbblfs0rvkxfg09bsz0g2mwmckrhga7idnarsnm8m565v1v";
      type = "gem";
    };
    version = "1.2.0";
  };
  sensu-extensions-only-check-output = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0ds2i8wd4ji9ifig2zzr4jpxinvk5dm7j10pvaqy4snykxa3rqh3";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-extensions-ruby-hash = {
    dependencies = ["sensu-extension"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1xyrj3gbmslbivcd5qcmyclgapn7qf7f5jwfvfpw53bxzib0h7s3";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-json = {
    dependencies = ["oj"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "08zlxg5j3bhs72cc7wcllp026jbif0xiw6ib1cgawndlpsfl9fgx";
      type = "gem";
    };
    version = "2.1.1";
  };
  sensu-logger = {
    dependencies = ["eventmachine" "sensu-json"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0jpw4kz36ilaknrzb3rbkhpbgv93w2d668z2cv395dq30d4d3iwm";
      type = "gem";
    };
    version = "1.2.2";
  };
  sensu-redis = {
    dependencies = ["eventmachine"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0widfmmj1h9ca2kk14wy1sqmlkq40linp89a73s3ghngnzri0xyk";
      type = "gem";
    };
    version = "2.4.0";
  };
  sensu-settings = {
    dependencies = ["parse-cron" "sensu-json"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1w3c63di23zqfml4r7f24j307r27digzqdccs8qkja88fbjawvrc";
      type = "gem";
    };
    version = "10.17.0";
  };
  sensu-spawn = {
    dependencies = ["childprocess" "em-worker" "eventmachine" "ffi"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "17yc8ivjpjbvig9r7yl6991d6ma0kcq75fbpz6i856ljvcr3lmd5";
      type = "gem";
    };
    version = "2.5.0";
  };
  sensu-transport = {
    dependencies = ["amq-protocol" "amqp" "eventmachine" "sensu-redis"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0baj3hlc1lr7w9ii65by83z4mn0k7xmjk48pss1y630859z5gzhb";
      type = "gem";
    };
    version = "8.3.0";
  };
}
