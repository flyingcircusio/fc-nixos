{
  lib,
  python,
  buildPythonApplication,
  parted,
  cryptsetup,
  lz4,
  blockdev,
  agent,
  mock,
  freezegun,
  requests,
  pytest,
  pytest_patterns,
  setuptools,
}:

buildPythonApplication rec {
  name = "fc-ceph-${version}";
  version = "2.1";
  src = ./.;
  dontStrip = true;

  pyproject = true;
  build-system = [ setuptools ];

  propagatedBuildInputs = [
    blockdev
    lz4
    agent
    requests
    cryptsetup
    parted
  ];

  passthru = {
    inherit checkInputs;
    py = python.pkgs;
  };

  checkInputs = [
    mock
    freezegun
    pytest_patterns
  ];

  nativeCheckInputs = [
    pytest
  ];

  meta = with lib; {
    description = "fc-ceph";
    maintainers = [
      maintainers.theuni
      maintainers.osnyx
    ];
    platforms = platforms.unix;
  };

  checkPhase = ''
    pytest -vv src/fc/ceph
  '';

}
