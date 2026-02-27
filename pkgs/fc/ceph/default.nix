{
  lib,
  buildPythonApplication,
  parted,
  cryptsetup,
  lz4,
  blockdev,
  agent,
  mock,
  freezegun,
  pytest,
  pytest_patterns,
  setuptools,
  nagiosplugin,
  rich,
  requests,
  ipy,
}:

buildPythonApplication rec {
  name = "fc-ceph-${version}";
  version = "2.1";
  src = ./.;
  dontStrip = true;

  pyproject = true;
  build-system = [ setuptools ];

  dependencies = [
    nagiosplugin
    rich
    requests
    ipy
  ];

  propagatedBuildInputs = [
    blockdev
    lz4
    agent
    cryptsetup
    parted
  ];

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
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

  checkPhase = ''
    pytest -vv src/fc/ceph
  '';

}
