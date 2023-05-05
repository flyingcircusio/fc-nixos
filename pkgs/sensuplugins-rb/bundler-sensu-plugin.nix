{ lib, bundlerApp, callPackage, defaultGemConfig, ruby_2_7 }:

with builtins;

{ pname,
  # List supported ruby scripts here
  exes,
  # Patch gems or add external build dependencies for gems here.
  # Will be merged into the default gem config.
  extraGemConfig ? {},
  meta ? null,
  postBuild ? ""
}@args:

bundlerApp {
  inherit pname exes;
  ruby = ruby_2_7;

  gemConfig = defaultGemConfig // extraGemConfig;
  gemdir = ./. + "/${pname}";

  # Calling ruby binstubs directly from Sensu doesn't work, because the Sensu bundle interferes with the plugin bundle.
  # Wrap ruby binstubs and call them with an emptied environment (env -i) that only sets HOME.
  # makeWrapper has no option for that, so we wrap manually here.
  # RUBYOPT silences annoying deprecation errors we cannot fix.
  postBuild = ''
    for prog in $out/bin/*.rb; do
      hidden="$(dirname "$prog")/.$(basename "$prog")"-wrapped
      mv $prog $hidden
      echo /usr/bin/env -i RUBYOPT=-W0 HOME=/tmp $hidden '"$@"' > $prog
      chmod a+x $prog
    done
  '' + postBuild;

  meta = if args ? meta then meta else {
    description = "Sensu community plugin ${pname}";
    homepage    = https://github.com/sensu-plugins/ + pname;
    platforms   = lib.platforms.unix;
  };
}
