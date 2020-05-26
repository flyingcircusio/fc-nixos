{ lib, rustPlatform, }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-postfix-${version}";
  version = "0.1.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };
  cargoSha256 = "1zq8j25f61wz316sgpxbqqzq6sc8hn7divsdb0l365sfr0fz1p48";

  meta = {
    description = ''
      Nagios/Sensu check to determine the number of mails in the queue
    '';
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
