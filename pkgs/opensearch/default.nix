{ lib
, stdenv
, fetchurl
, makeWrapper
, jre_headless
, util-linux
, gnugrep
, coreutils
, autoPatchelfHook
, zlib
}:

with lib;
let
  info = splitString "-" stdenv.hostPlatform.system;
  arch = "x64";
  plat = elemAt info 1;
  shas =
    {
      x86_64-linux  = "0qazhz0iqs23fd986wpz4w8a49c2gkrjs93if7xjbk57m443r1m5";
      #x86_64-darwin = "05h7pvq4pb816wgcymnfklp3w6sv54x6138v2infw5219dnk8pfs";
      #aarch64-linux = "0q4xnjzhlx1b2lkikca88qh9glfxaifsm419k2bxxlrfrx31zlkq";
    };
in
stdenv.mkDerivation rec {
  version = "1.3.1";
  pname = "opensearch";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch/${version}/${pname}-${version}-${plat}-${arch}.tar.gz";
    sha256 = shas.${stdenv.hostPlatform.system} or (throw "Unknown architecture");
  };

  patches = [ ./opensearch-home.patch ];

  postPatch = ''
    substituteInPlace bin/opensearch-env --replace \
      "OPENSEARCH_CLASSPATH=\"\$OPENSEARCH_HOME/lib/*\"" \
      "OPENSEARCH_CLASSPATH=\"$out/lib/*\""

    substituteInPlace bin/opensearch-cli --replace \
      "OPENSEARCH_CLASSPATH=\"\$OPENSEARCH_CLASSPATH:\$OPENSEARCH_HOME/\$additional_classpath_directory/*\"" \
      "OPENSEARCH_CLASSPATH=\"\$OPENSEARCH_CLASSPATH:$out/\$additional_classpath_directory/*\""
  '';

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [ jre_headless util-linux zlib stdenv.cc.cc.lib ];

  runtimeDependencies = [ zlib stdenv.cc.cc.lib ];

  installPhase = ''
    mkdir -p $out
    cp -R bin config lib modules plugins $out

    chmod +x $out/bin/*

    substituteInPlace $out/bin/opensearch \
      --replace 'bin/opensearch-keystore' "$out/bin/opensearch-keystore"

    wrapProgram $out/bin/opensearch \
      --prefix PATH : "${makeBinPath [ util-linux coreutils gnugrep ]}" \
      --set JAVA_HOME "${jre_headless}"

    ln -s $out/bin/opensearch $out/bin/elasticsearch

    wrapProgram $out/bin/opensearch-plugin --set JAVA_HOME "${jre_headless}"
  '';

  meta = {
    description = "Open Source, Distributed, RESTful Search Engine";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}
