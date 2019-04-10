{ lib, bundlerEnv, ruby, mysql, redis, which, defaultGemConfig, zlib, libxml2, graphicsmagick, pkgconfig, imagemagickBig, cyrus_sasl, makeWrapper }:

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

  # Calling ruby binstubs directly from Sensu doesn't work, because the Sensu bundle interferes with the plugin bundle.
  # Wrap ruby binstubs and call them with an empty environment (env -i).
  # makeWrapper has no option for that, so we wrap manually here.
  postBuild = ''
    for prog in $out/bin/*.rb; do
      hidden="$(dirname "$prog")/.$(basename "$prog")"-wrapped
      mv $prog $hidden
      echo "/usr/bin/env -i - $hidden \"$@\"" > $prog
      chmod a+x $prog
    done
  '';

  meta = with lib; {
    description = "A collection of Sensu plugins distributed as Rubygems";
    homepage    = https://github.com/sensu-plugins/;
    platforms   = platforms.unix;
  };
}
