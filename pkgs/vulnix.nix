{ stdenv, python3Packages, nix, ronn, fetchFromGitHub }:

python3Packages.buildPythonApplication rec {
  pname = "vulnix";
  version = "1.9.3-pre";

  # src = python3Packages.fetchPypi {
  #   inherit pname version;
  #   sha256 = "06mi4a80g6nzvqxj51c7lc0q0dpdr603ly2r77ksf5m3k4glb6dm";
  # };

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "vulnix";
    rev = "6d22b78ca498fb00198c1c010ff86d99daf2c17c";
    sha256 = "1678fl5zs730ynvkc6vxmsd89miaxvzbrg3ga5yjg32gcchdi8hl";
  };

  outputs = [ "out" "doc" "man" ];
  nativeBuildInputs = [ ronn ];

  checkInputs = with python3Packages; [
    freezegun
    pytest
    pytestcov
    pytest-flake8
  ];

  propagatedBuildInputs = [
    nix
  ] ++ (with python3Packages; [
    click
    colorama
    pyyaml
    requests
    setuptools
    toml
    zodb
  ]);

  postBuild = "make -C doc";

  checkPhase = "py.test src/vulnix";

  postInstall = ''
    install -D -t $doc/share/doc/vulnix README.rst CHANGES.rst
    gzip $doc/share/doc/vulnix/*.rst
    install -D -t $man/share/man/man1 doc/vulnix.1
    install -D -t $man/share/man/man5 doc/vulnix-whitelist.5
  '';

  dontStrip = true;

  meta = with stdenv.lib; {
    description = "NixOS vulnerability scanner";
    homepage = "https://github.com/flyingcircusio/vulnix";
    license = licenses.bsd3;
    maintainers = with maintainers; [ ckauhaus ];
  };
}
