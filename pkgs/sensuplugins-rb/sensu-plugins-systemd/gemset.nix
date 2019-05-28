{
  json = {
    source = {
      remotes = ["http://rubygems.org"];
      sha256 = "0sx97bm9by389rbzv8r1f43h06xcz8vwi3h5jv074gvparql7lcx";
      type = "gem";
    };
    version = "2.2.0";
  };
  mixlib-cli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "050mjilikw7am0g7yw5qpsz6y7aj98f3x3c5zcwnwkyldn5ri5jc";
      type = "gem";
    };
    version = "2.0.6";
  };
  ruby-dbus = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1ga8q959i8j8iljnw9hgxnjlqz1q0f95p9r3hyx6r5fl657qbx8z";
      type = "gem";
    };
    version = "0.11.0";
  };
  sensu-plugin = {
    dependencies = ["json" "mixlib-cli"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1k8mkkwb70z2j5lq457y7lsh5hr8gzd53sjbavpqpfgy6g4bxrg8";
      type = "gem";
    };
    version = "1.2.0";
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
  systemd-bindings = {
    dependencies = ["ruby-dbus"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1bprj8njmzbshjmrabra3djhw6737hn9mm0n8sxb7wv1znpr7lds";
      type = "gem";
    };
    version = "0.0.1.1";
  };
}