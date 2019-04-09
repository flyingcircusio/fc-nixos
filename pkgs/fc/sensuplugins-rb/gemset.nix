{
  activesupport = {
    dependencies = ["i18n" "minitest" "thread_safe" "tzinfo"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1vbq7a805bfvyik2q3kl9s3r418f5qzvysqbz2cwy4hr7m2q4ir6";
      type = "gem";
    };
    version = "4.2.11.1";
  };
  addressable = {
    dependencies = ["public_suffix"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0bcm2hchn897xjhqj9zzsxf3n9xhddymj4lsclz508f4vw3av46l";
      type = "gem";
    };
    version = "2.6.0";
  };
  aws-es-transport = {
    dependencies = ["aws-sdk" "elasticsearch" "faraday" "faraday_middleware"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1r2if0jcbw3xx019fs6lqkz65nffwgh7hjbh5fj13hi09g505m3m";
      type = "gem";
    };
    version = "0.1.4";
  };
  aws-sdk = {
    dependencies = ["aws-sdk-resources"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0wxvkzn7nsp5r09z3428cmzzzpkjdqmcwgwsfmm3clb93k9ivchv";
      type = "gem";
    };
    version = "2.4.4";
  };
  aws-sdk-core = {
    dependencies = ["jmespath"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0v624h6yv28vbmcskx6n67blzq2an0171wcppkr3sx335wi4hriw";
      type = "gem";
    };
    version = "2.4.4";
  };
  aws-sdk-resources = {
    dependencies = ["aws-sdk-core"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1a1lxkig0d2ihv8f581nq65z4b2cf89mg753mvkh8b1kh9ipybx4";
      type = "gem";
    };
    version = "2.4.4";
  };
  aws-ses = {
    dependencies = ["builder" "mail" "mime-types" "xml-simple"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0dssck23xhm1x4lz9llflvxc5hi17zpgshb32p9xpja7kwv035pf";
      type = "gem";
    };
    version = "0.6.0";
  };
  bson = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1kgim98b41cj0njlqv1bwvx2m6gw9n7ilwklfn9hivfg096bzl8l";
      type = "gem";
    };
    version = "4.4.2";
  };
  builder = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0qibi5s67lpdv1wgcj66wcymcr04q6j4mzws6a479n0mlrmh5wr1";
      type = "gem";
    };
    version = "3.2.3";
  };
  concurrent-ruby = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1x07r23s7836cpp5z9yrlbpljcxpax14yw4fy4bnp6crhr6x24an";
      type = "gem";
    };
    version = "1.1.5";
  };
  dalli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0zr66q3ndc0yd17hxll8y0j1j33y4kxw5cgjpvfpdc27wflcxx4i";
      type = "gem";
    };
    version = "2.7.10";
  };
  dentaku = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "18ga010bbhsgc876vf6z6swfnk2mgj30y96rcd4yafvmwnj5djgz";
      type = "gem";
    };
    version = "2.0.4";
  };
  dnsbl-client = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1357r0y8xfnay05l9h26rrcqrjlnz0hy421g18pfrwm1psf3pp04";
      type = "gem";
    };
    version = "1.0.2";
  };
  dnsruby = {
    dependencies = ["addressable"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "04sxvjif1pxmlf02mj3hkdb209pq18fv9sr2p0mxwi0dpifk6f3x";
      type = "gem";
    };
    version = "1.61.2";
  };
  domain_name = {
    dependencies = ["unf"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0abdlwb64ns7ssmiqhdwgl27ly40x2l27l8hs8hn0z4kb3zd2x3v";
      type = "gem";
    };
    version = "0.5.20180417";
  };
  elasticsearch = {
    dependencies = ["elasticsearch-api" "elasticsearch-transport"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1wdy17i56b4m7akp7yavnr8vhfhyz720waphmixq05dj21b11hl0";
      type = "gem";
    };
    version = "1.0.18";
  };
  elasticsearch-api = {
    dependencies = ["multi_json"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1v6nb3ajz5rack3p4b4nz37hs0zb9x738h2ms8cc4plp6wqh1w5s";
      type = "gem";
    };
    version = "1.0.18";
  };
  elasticsearch-transport = {
    dependencies = ["faraday" "multi_json"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0smfrz8nq49hgf67y5ayxa9i4rmmi0q4m51l0h499ykq4cvcwv6i";
      type = "gem";
    };
    version = "1.0.18";
  };
  erubis = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1fj827xqjs91yqsydf0zmfyw9p4l2jz5yikg3mppz6d7fi8kyrb3";
      type = "gem";
    };
    version = "2.7.0";
  };
  faraday = {
    dependencies = ["multipart-post"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1kplqkpn2s2yl3lxdf6h7sfldqvkbkpxwwxhyk7mdhjplb5faqh6";
      type = "gem";
    };
    version = "0.9.2";
  };
  faraday_middleware = {
    dependencies = ["faraday"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "18jndnpls6aih57rlkzdq94m5r7zlkjngyirv01jqlxll8jy643r";
      type = "gem";
    };
    version = "0.10.1";
  };
  ffi = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0j8pzj8raxbir5w5k6s7a042sb5k02pg0f8s4na1r5lan901j00p";
      type = "gem";
    };
    version = "1.10.0";
  };
  http-cookie = {
    dependencies = ["domain_name"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "004cgs4xg5n6byjs7qld0xhsjq3n6ydfh897myr2mibvh6fjc49g";
      type = "gem";
    };
    version = "1.0.3";
  };
  i18n = {
    dependencies = ["concurrent-ruby"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "038qvz7kd3cfxk8bvagqhakx68pfbnmghpdkx7573wbf0maqp9a3";
      type = "gem";
    };
    version = "0.9.5";
  };
  inifile = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1c5zmk7ia63yw5l2k14qhfdydxwi1sah1ppjdiicr4zcalvfn0xi";
      type = "gem";
    };
    version = "3.0.0";
  };
  jmespath = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1d4wac0dcd1jf6kc57891glih9w57552zgqswgy74d1xhgnk0ngf";
      type = "gem";
    };
    version = "1.4.0";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0qmj7fypgb9vag723w1a49qihxrcf5shzars106ynw2zk352gbv5";
      type = "gem";
    };
    version = "1.8.6";
  };
  mail = {
    dependencies = ["mime-types"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1nbg60h3cpnys45h7zydxwrl200p7ksvmrbxnwwbpaaf9vnf3znp";
      type = "gem";
    };
    version = "2.6.3";
  };
  mailgun-ruby = {
    dependencies = ["json" "rest-client"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1aqa0ispfn27g20s8s517cykghycxps0bydqargx7687w6d320yb";
      type = "gem";
    };
    version = "1.0.3";
  };
  mime-types = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "03j98xr0qw2p2jkclpmk7pm29yvmmh0073d8d43ajmr0h3w7i5l9";
      type = "gem";
    };
    version = "2.99.3";
  };
  minitest = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0icglrhghgwdlnzzp4jf76b0mbc71s80njn5afyfjn4wqji8mqbq";
      type = "gem";
    };
    version = "5.11.3";
  };
  mixlib-cli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0zzdcvsdvvs44wbyggjgzkr2sqs6sz2l693mqngakvy1apzv3f1c";
      type = "gem";
    };
    version = "2.0.3";
  };
  mongo = {
    dependencies = ["bson"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "07gs4ll8hm1paj3liblpy0zqxidvcxb76cxa47l0i23mbf5hp46v";
      type = "gem";
    };
    version = "2.4.1";
  };
  multi_json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1rl0qy4inf1mp8mybfk56dfga0mvx97zwpmq5xmiwl5r770171nv";
      type = "gem";
    };
    version = "1.13.1";
  };
  multipart-post = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "09k0b3cybqilk1gwrwwain95rdypixb2q9w65gd44gfzsd84xi1x";
      type = "gem";
    };
    version = "2.0.0";
  };
  net-ping = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "19p3d39109xvbr4dcjs3g3zliazhc1k3iiw69mgb1w204hc7wkih";
      type = "gem";
    };
    version = "1.7.8";
  };
  netrc = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0gzfmcywp1da8nzfqsql2zqi648mfnx6qwkig3cv36n9m0yy676y";
      type = "gem";
    };
    version = "0.11.0";
  };
  pg = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "00g33hdixgync6gp4mn0g0kjz5qygshi47xw58kdpd9n5lzdpg8c";
      type = "gem";
    };
    version = "0.18.3";
  };
  public_suffix = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "040jf98jpp6w140ghkhw2hvc1qx41zvywx5gj7r2ylr1148qnj7q";
      type = "gem";
    };
    version = "2.0.5";
  };
  redis = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0i415x8gi0c5vsiy6ikvx5js6fhc4x80a5lqv8iidy2iymd20irv";
      type = "gem";
    };
    version = "3.3.5";
  };
  rest-client = {
    dependencies = ["http-cookie" "mime-types" "netrc"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1m8z0c4yf6w47iqz6j2p7x1ip4qnnzvhdph9d5fgx081cvjly3p7";
      type = "gem";
    };
    version = "1.8.0";
  };
  ruby-dbus = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1ga8q959i8j8iljnw9hgxnjlqz1q0f95p9r3hyx6r5fl657qbx8z";
      type = "gem";
    };
    version = "0.11.0";
  };
  ruby-mysql = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0agxhs8ghmhnwvy6f8pb2wgynrlpjkcy9nqjxx8clw21k436b5nk";
      type = "gem";
    };
    version = "2.9.14";
  };
  ruby-ntlm = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1xg4wjxhv19n04q8knb2ac9mmdiqp88rc1dkzdxcmy0wrn2w2j0n";
      type = "gem";
    };
    version = "0.0.3";
  };
  sensu-plugin = {
    dependencies = ["json" "mixlib-cli"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1k8mkkwb70z2j5lq457y7lsh5hr8gzd53sjbavpqpfgy6g4bxrg8";
      type = "gem";
    };
    version = "1.2.0";
  };
  sensu-plugins-disk-checks = {
    dependencies = ["sensu-plugin" "sys-filesystem"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0q4f23ccvl6d0k26xph2fskk5pv2mmdrclr00m358m880sgkhyg1";
      type = "gem";
    };
    version = "4.0.1";
  };
  sensu-plugins-dns = {
    dependencies = ["dnsruby" "public_suffix" "sensu-plugin" "whois" "whois-parser"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1pqf9w8z4sfj43fr30hxdmnfa1lj2apkc0bm6jz851bmj9bzqahl";
      type = "gem";
    };
    version = "2.1.1";
  };
  sensu-plugins-elasticsearch = {
    dependencies = ["aws-es-transport" "aws-sdk" "elasticsearch" "rest-client" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0l4fpw549dyp5b2c975lyg9287dpmsg9d2ppk7ry109zs1zx8khy";
      type = "gem";
    };
    version = "3.0.0";
  };
  sensu-plugins-entropy-checks = {
    dependencies = ["sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "17s132bkzidw2lm7jj3qnsvna8p8ria19pbrmdsb8g8xfavf0xj0";
      type = "gem";
    };
    version = "1.0.0";
  };
  sensu-plugins-logs = {
    dependencies = ["sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "17shj4msc8bzqgqi5waw649hzzgl8q87z6flmpg0msnmv4r2h1cf";
      type = "gem";
    };
    version = "1.3.2";
  };
  sensu-plugins-mailer = {
    dependencies = ["aws-ses" "erubis" "mail" "mailgun-ruby" "ruby-ntlm" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1yxdkrjkdqcqy7829m38zm0imwgqnb0242hszlq4b68b695c0y9l";
      type = "gem";
    };
    version = "2.1.0";
  };
  sensu-plugins-memcached = {
    dependencies = ["dalli" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1wlqlv2gpgapd4lfbyxlk09qw9jypbcg8ankjfds7z1rx6p7cxq5";
      type = "gem";
    };
    version = "0.1.3";
  };
  sensu-plugins-mongodb = {
    dependencies = ["bson" "mongo" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0r4pgn06n3pyvas75igfy969z3hv1gbrwbf4cqvy88h9aqn5dw5a";
      type = "gem";
    };
    version = "1.4.1";
  };
  sensu-plugins-mysql = {
    dependencies = ["inifile" "ruby-mysql" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0jxmd99yysb8bwkvy7ll7ih4mk6r8rsmj8lvz6q1alaiyprga9vn";
      type = "gem";
    };
    version = "3.1.1";
  };
  sensu-plugins-network-checks = {
    dependencies = ["activesupport" "dnsbl-client" "net-ping" "sensu-plugin" "whois" "whois-parser"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0pyv7n3dj05442f5c3h2028dd93359a4aqv7xhgdj5jnyd9yqc07";
      type = "gem";
    };
    version = "3.2.1";
  };
  sensu-plugins-postgres = {
    dependencies = ["dentaku" "pg" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0sk1sqqs6c3wdc7cl3pqrb5pfbaqn88fjyik0bvhli8c8wds0h1v";
      type = "gem";
    };
    version = "2.3.2";
  };
  sensu-plugins-redis = {
    dependencies = ["redis" "sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1kl9lf0fixvf6zm887bpqhxhbjaayx3b1smp2a3hwnf6kgmym0x5";
      type = "gem";
    };
    version = "3.1.1";
  };
  sensu-plugins-ssl = {
    dependencies = ["sensu-plugin"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0y5mly4wrhgnfp4cp54yjmyscy3gqnyvbyaw7ymjw50fg55d0syy";
      type = "gem";
    };
    version = "2.0.1";
  };
  sensu-plugins-systemd = {
    dependencies = ["sensu-plugin" "systemd-bindings"];
    groups = ["default"];
    platforms = [];
    source = {
      fetchSubmodules = false;
      rev = "be972959c5f6cdc989b1122db72a4b10a1ecce77";
      sha256 = "0n1jbzs4ls4gmci8zc92nm3mi1n69w2i37k28zlfwxazbm1gyy0z";
      type = "git";
      url = "https://github.com/nyxcharon/sensu-plugins-systemd.git";
    };
    version = "0.0.1";
  };
  sys-filesystem = {
    dependencies = ["ffi"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "10didky52nfapmybj6ipda18i8fcwf8bs9bbfbk5i7v1shzd36rf";
      type = "gem";
    };
    version = "1.1.7";
  };
  systemd-bindings = {
    dependencies = ["ruby-dbus"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1bprj8njmzbshjmrabra3djhw6737hn9mm0n8sxb7wv1znpr7lds";
      type = "gem";
    };
    version = "0.0.1.1";
  };
  thread_safe = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0nmhcgq6cgz44srylra07bmaw99f5271l0dpsvl5f75m44l0gmwy";
      type = "gem";
    };
    version = "0.3.6";
  };
  tzinfo = {
    dependencies = ["thread_safe"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "1fjx9j327xpkkdlxwmkl3a8wqj7i4l4jwlrv3z13mg95z9wl253z";
      type = "gem";
    };
    version = "1.2.5";
  };
  unf = {
    dependencies = ["unf_ext"];
    groups = ["default"];
    platforms = [];
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
      remotes = ["http://rubygems.org"];
      sha256 = "06p1i6qhy34bpb8q8ms88y6f2kz86azwm098yvcc0nyqk9y729j1";
      type = "gem";
    };
    version = "0.0.7.5";
  };
  whois = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0mmkibflh7xk2dpfmpw2gsranb7xv6hx51vzkphlh0fv59gmjhcz";
      type = "gem";
    };
    version = "4.0.8";
  };
  whois-parser = {
    dependencies = ["activesupport" "whois"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "076b23j506qvy5vk60a0sy7krl12crfzjymffwc0b54wqc63i7fq";
      type = "gem";
    };
    version = "1.0.1";
  };
  xml-simple = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0xlqplda3fix5pcykzsyzwgnbamb3qrqkgbrhhfz2a2fxhrkvhw8";
      type = "gem";
    };
    version = "1.1.5";
  };
}