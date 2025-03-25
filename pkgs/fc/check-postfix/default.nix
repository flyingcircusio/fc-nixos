{ lib, rustPlatform }:

with lib;

rustPlatform.buildRustPackage rec {
  name = "check-postfix-${version}";
  version = "0.1.0";

  src = cleanSourceWith {
    filter = n: t: baseNameOf n != "target";
    src = cleanSource ./.;
  };

  # FIXME: need to migrate to new cargo fetcher, but currently generates
  # a key error during locking.
  #useFetchCargoVendor = true;
  cargoHash = "sha256-iNzwHchOFzMoWE3v2I6FiGmDP8ar36dNGJ8H44qQCP8=";

  meta = {
    description = ''
      Nagios/Sensu check to determine the number of mails in the queue
    '';
    license = licenses.zpl21;
    maintainer = with maintainers; [ ckauhaus ];
  };
}
