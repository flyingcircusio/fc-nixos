{ lib, callPackage, bundlerApp, defaultGemConfig, postfix, gnugrep, ruby }:

bundlerApp rec {
  inherit ruby;

  pname = "sensu-plugins-postfix";
  gemdir = ./.;
  # list supported scripts here
  exes = [ "check-mailq.rb" ];

  gemConfig = defaultGemConfig // {
    sensu-plugins-postfix = attrs: {
      buildInputs = [ postfix gnugrep ];
      dontBuild = false;
      postPatch = ''
        substituteInPlace bin/check-mailq.rb \
          --replace /bin/egrep ${gnugrep}/bin/egrep \
          --replace /usr/bin/mailq ${postfix}/bin/mailq
      '';
    };
  };

  # bundled sensu plugins need a clean env so that they don't inherit the bundle from sensu itself
  postBuild = (callPackage ../common.nix {}).postBuildCleanEnv;

  meta = with lib; {
    description = "Provides native Postfix instrumentation for monitoring and metrics collection of the mail queue via `mailq";
    homepage    = https://github.com/sensu-plugins/sensu-plugins-postfix;
    platforms   = platforms.unix;
  };
}
