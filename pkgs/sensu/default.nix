{ lib, ruby_2_7, bundlerApp, bundlerUpdateScript }:

bundlerApp {
  ruby = ruby_2_7;
  pname = "sensu";
  gemdir = ./.;
  exes = [
    "sensu-client"
  ];

  meta = with lib; {
    description = "A monitoring framework that aims to be simple, malleable, and scalable";
    homepage    = "https://sensuapp.org/";
    license     = licenses.mit;
    maintainers = with maintainers; [ theuni peterhoeg manveru nicknovitski ];
    platforms   = platforms.unix;
  };
}
