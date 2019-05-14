{ }:
{
  # Calling ruby binstubs directly from Sensu doesn't work, because the Sensu bundle interferes with the plugin bundle.
  # Wrap ruby binstubs and call them with an empty environment (env -i).
  # makeWrapper has no option for that, so we wrap manually here.
  postBuildCleanEnv = ''
    for prog in $out/bin/*.rb; do
      hidden="$(dirname "$prog")/.$(basename "$prog")"-wrapped
      mv $prog $hidden
      echo /usr/bin/env -i - $hidden '"$@"' > $prog
      chmod a+x $prog
    done
  '';
}
