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
  requests,
  pytest,
  pytest_patterns,
}:

buildPythonApplication rec {
  name = "fc-ceph-${version}";
  version = "2.1";
  src = ./.;
  dontStrip = true;
  propagatedBuildInputs = [
    blockdev
    lz4
    agent
    requests
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
