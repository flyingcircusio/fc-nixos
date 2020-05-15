{ lib, rustPlatform, }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-postfix-${version}";
  version = "0.1.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };
  cargoSha256 = "1s771jlf0vlxqqhh5nzr8i3rpi57gkpjmiv82d06qzh6p4sgngl7";

  meta = {
    description = ''
      Nagios/Sensu check to determine the number of mails in the queue
    '';
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
