{ lib, ruby, bundlerApp, bundlerUpdateScript }:

bundlerApp {
  inherit ruby;
  pname = "sensu";
  gemdir = ./.;
  exes = [
    "sensu-api"
    "sensu-client"
    "sensu-install"
    "sensu-server"
  ];

  passthru.updateScript = bundlerUpdateScript "sensu";

  meta = with lib; {
    description = "A monitoring framework that aims to be simple, malleable, and scalable";
    homepage    = "https://sensuapp.org/";
    license     = licenses.mit;
    maintainers = with maintainers; [ theuni peterhoeg manveru nicknovitski ];
    platforms   = platforms.unix;
  };
}
