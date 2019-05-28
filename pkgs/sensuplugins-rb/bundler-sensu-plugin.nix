{ lib, bundlerApp, callPackage, defaultGemConfig, ruby }:

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
  inherit pname exes ruby;

  gemConfig = defaultGemConfig // extraGemConfig;
  gemdir = ./. + "/${pname}";

  # Calling ruby binstubs directly from Sensu doesn't work, because the Sensu bundle interferes with the plugin bundle.
  # Wrap ruby binstubs and call them with an empty environment (env -i).
  # makeWrapper has no option for that, so we wrap manually here.
  postBuild = ''
    for prog in $out/bin/*.rb; do
      hidden="$(dirname "$prog")/.$(basename "$prog")"-wrapped
      mv $prog $hidden
      echo /usr/bin/env -i - $hidden '"$@"' > $prog
      chmod a+x $prog
    done
  '' + postBuild;

  meta = if args ? meta then meta else {
    description = "Sensu community plugin ${pname}";
    homepage    = https://github.com/sensu-plugins/ + pname;
    platforms   = lib.platforms.unix;
  };
}
