{ runCommand
, stdenv
, easyrsa
, openvpn
, gawk
, resource_group ? "unknown-rg"
, location ? "standalone"
, caDir ? "/var/lib/openvpn-pki"
, gnused
}:

{
  generate = runCommand "generate-pki.sh" {
    inherit easyrsa openvpn gawk resource_group location gnused caDir;
    inherit (stdenv) shell;
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    substituteAll ${./generate-pki.sh} $out
    chmod +x $out
    # check if script can be executed
    $shell -n $out
  '';

  inherit caDir;
  caCrt = "${caDir}/pki/ca.crt";
  serverCrt = "${caDir}/server.crt";
  serverKey = "${caDir}/server.key";
  clientCrt = "${caDir}/client.crt";
  clientKey = "${caDir}/client.key";
  dh = "${caDir}/pki/dh.pem";
  ta = "${caDir}/ta.key";
}
