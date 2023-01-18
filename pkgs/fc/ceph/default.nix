{ lib, stdenv, python3Full, python3Packages, lz4, blockdev, lvm2, utillinux, agent, util-physical }:

let
  py = python3Packages;
in

py.buildPythonApplication rec {
  name = "fc-ceph-${version}";
  version = "2.1";
  src = ./.;
  dontStrip = true;
  propagatedBuildInputs = [
    blockdev
    lz4
    agent
    util-physical
    python3Packages.requests
  ];

  checkInputs = [
        python3Packages.pytest
        python3Packages.mock
        python3Packages.freezegun
  ];

  meta = with lib; {
    description = "fc-ceph";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

  checkPhase = ''
    pytest src/fc/ceph
  '';

}
