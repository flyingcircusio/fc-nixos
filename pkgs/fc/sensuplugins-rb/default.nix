{ lib, bundlerEnv, callPackage, defaultGemConfig, ruby, mysql, redis, which,
  zlib, libxml2, graphicsmagick, pkgconfig, imagemagickBig, cyrus_sasl }:

bundlerEnv rec {
  inherit ruby;

  name = "sensuplugins-rb";
  gemdir = ./.;

  gemConfig = defaultGemConfig // {
    libxml-ruby = attrs: {
      buildInputs = [ zlib ];
      preInstall = ''
        bundle config build.libxml-ruby "--use-system-libraries --with-xml2-lib=${libxml2}/lib --with-xml2-include=${libxml2}/include/libxml2"
      '';
    };
    rmagick = attrs: {
      buildInputs = [ which graphicsmagick pkgconfig imagemagickBig ];
    };
    mysql = attrs: {
      buildInputs = [ mysql ];
    };
    redis = attrs: {
      buildInputs = [ redis ];
    };
    memcached = attrs: {
      buildInputs = [ cyrus_sasl ];
    };
  };

  # bundled sensu plugins need a clean env so that they don't inherit the bundle from sensu itself
  postBuild = (callPackage ./common.nix {}).postBuildCleanEnv;

  meta = with lib; {
    description = "A collection of Sensu plugins distributed as Rubygems";
    homepage    = https://github.com/sensu-plugins/;
    platforms   = platforms.unix;
  };
}
