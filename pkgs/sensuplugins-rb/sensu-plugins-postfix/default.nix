{ lib, bundlerSensuPlugin, gnugrep, postfix }:

bundlerSensuPlugin rec {
  pname = "sensu-plugins-postfix";
  exes = [ "check-mailq.rb" ];

  extraGemConfig = {
    sensu-plugins-postfix = attrs: {
      buildInputs = [ gnugrep postfix ];
      dontBuild = false;
      postPatch = ''
        substituteInPlace bin/check-mailq.rb \
          --replace /bin/egrep ${gnugrep}/bin/egrep \
          --replace /usr/bin/mailq ${postfix}/bin/mailq
      '';
    };
  };
}
