{ lib, stdenv, fetchFromGitHub
, autoreconfHook, bison, flex, pkg-config
, curl, geoip, libmaxminddb, libxml2, lua, pcre, ssdeep, yajl
, nixosTests
}:

stdenv.mkDerivation rec {
  pname = "libmodsecurity";
  version = "3.0.12";

  src = fetchFromGitHub {
    owner = "SpiderLabs";
    repo = "ModSecurity";
    rev = "v${version}";
    sha256 = "sha256-WIFAg9LvKAC8e3gpcIxtNHT53AIfPtUTyrv30woxP4M=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ autoreconfHook bison flex pkg-config ];
  buildInputs = [ curl geoip libmaxminddb libxml2 lua pcre ssdeep yajl ];

  outputs = [ "out" "dev" ];

  configureFlags = [
    "--enable-parser-generation"
    "--disable-doxygen-doc"
    "--with-curl=${curl.dev}"
    "--with-libxml=${libxml2.dev}"
    "--with-maxmind=${libmaxminddb}"
    "--with-pcre=${pcre.dev}"
    "--with-ssdeep=${ssdeep}"
  ];

  postPatch = ''
    substituteInPlace build/ssdeep.m4 \
      --replace "/usr/local/libfuzzy" "${ssdeep}/lib" \
      --replace "\''${path}/include/fuzzy.h" "${ssdeep}/include/fuzzy.h" \
      --replace "ssdeep_inc_path=\"\''${path}/include\"" "ssdeep_inc_path=\"${ssdeep}/include\""
    substituteInPlace modsecurity.conf-recommended \
      --replace "SecUnicodeMapFile unicode.mapping 20127" "SecUnicodeMapFile $out/share/modsecurity/unicode.mapping 20127"
  '';

  postInstall = ''
    mkdir -p $out/share/modsecurity
    cp ${src}/{AUTHORS,CHANGES,LICENSE,README.md,modsecurity.conf-recommended,unicode.mapping} $out/share/modsecurity
  '';

  enableParallelBuilding = true;

  passthru.tests = {
    nginx-modsecurity = nixosTests.nginx-modsecurity;
  };

  meta = with lib; {
    homepage = "https://github.com/SpiderLabs/ModSecurity";
    description = ''
      ModSecurity v3 library component.
    '';
    longDescription = ''
      Libmodsecurity is one component of the ModSecurity v3 project. The
      library codebase serves as an interface to ModSecurity Connectors taking
      in web traffic and applying traditional ModSecurity processing. In
      general, it provides the capability to load/interpret rules written in
      the ModSecurity SecRules format and apply them to HTTP content provided
      by your application via Connectors.
    '';
    license = licenses.asl20;
    platforms = platforms.all;
    maintainers = with maintainers; [ izorkin ];
    mainProgram = "modsec-rules-check";
  };
}
