{
  lib,
  stdenv,
  bash,
  fetchurl,
  jre,
  makeWrapper,
}:
let
  generic =
    {
      version,
      hash,
      url ? "mirror://apache/solr/solr/${version}/solr-${version}.tgz",
      additionalInstallCommands ? "",
    }:
    stdenv.mkDerivation {
      pname = "solr";
      inherit version;

      src = fetchurl {
        inherit url hash;
      };

      nativeBuildInputs = [ makeWrapper ];
      buildInputs = [ bash ]; # non interactive bash does not provide compgen

      installPhase = ''
        mkdir -p $out $out/bin

        cp -r bin/solr $out/bin/
        cp -r example $out/
        cp -r server $out/

        wrapProgram $out/bin/solr --set JAVA_HOME "${jre}"
      ''
      + additionalInstallCommands;

      meta = with lib; {
        homepage = "https://solr.apache.org/";
        description = "Open source enterprise search platform from the Apache Lucene project";
        license = licenses.asl20;
        mainProgram = "solr";
        platforms = platforms.all;
      };
    };
in
{
  solr_8 = generic rec {
    version = "8.11.4";
    hash = "sha256-Fj+98ka714kQvDbDJXrVDN8xzMMyml74hcI8nvaeDr4=";
    url = "mirror://apache/lucene/solr/${version}/solr-${version}.tgz";
    additionalInstallCommands = ''
      cp -r contrib $out/
      cp -r dist $out/
      cp -r bin/post $out/bin/
      wrapProgram $out/bin/post --set JAVA_HOME "${jre}"
    '';
  };
  solr_9 = generic {
    version = "9.10.1";
    hash = "sha256-Md2Rrq3lQPTXAFzBoffMWDrXenjYAMkGXKwGrxsJdFQ=";
    additionalInstallCommands = ''
      cp -r bin/post $out/bin/
      wrapProgram $out/bin/post --set JAVA_HOME "${jre}"
    '';
  };
  solr_10 = generic {
    version = "10.0.0";
    hash = "sha256-B8GAlw9g0Td2vhPMtgxwfQQeXhqLkU0ZfRNYrCX4BLU=";
  };
}
