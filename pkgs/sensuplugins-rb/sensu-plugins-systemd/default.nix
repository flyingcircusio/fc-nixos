{ bundlerEnv, stdenv, ruby }:

let
  gems = bundlerEnv {
    gemdir = ./.;
    name = "sensu-plugin-systemd-gems";
  };

in
  stdenv.mkDerivation {
    name = "sensu-plugin-systemd";
    version = "0.1";

    src = ./check-failed-units.rb;

    phases = [ "installPhase" "fixupPhase" ];
    buildInputs = [ gems ];
    propagatedBuildInputs = [ ruby ];

    installPhase = ''
      mkdir -p $out/bin
      prog=$out/bin/check-failed-units.rb
      wrapped=$out/bin/.check-failed-units.rb-wrapped
      cp $src $wrapped

      echo /usr/bin/env -i HOME=/tmp ${gems}/bin/bundle exec $wrapped '"$@"' > $prog
      chmod 755 $prog
    '';

  }
