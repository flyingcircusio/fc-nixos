{
  config,
  lib,
  pkgs,
  ...
}:

# This file needs to be kept (somewhat) in sync with our
# `kvm_host_ceph-nautilus.nix` in the platform.
let
  fclib = config.fclib;
  testPackage = config.flyingcircus.services.ceph.fc-ceph.package;
in
{

  environment.systemPackages =
    let
      testPackages = ([ testPackage ] ++ testPackage.propagatedBuildInputs ++ testPackage.checkInputs);
      PYTHONPATH = testPackage.py.makePythonPath testPackages;
      PATH = lib.makeBinPath testPackages;
    in
    [
      (pkgs.writeShellScriptBin "run-tests" ''
        set -o pipefail
        export PYTHONPATH="${PYTHONPATH}"
        export PATH="${PATH}:${pkgs.openssh}/bin:${pkgs.gnused}/bin"
        cd ${testPackage.src}
        pytest -vv --cov-config=/etc/coveragerc --cov-append -c ${testPackage.src}/pytest.ini "$@"
      '')
    ];

  environment.etc."coveragerc".text = ''
    [run]
    data_file = /tmp/coverage/data

    [html]
    directory = /tmp/coverage/html
  '';

  environment.sessionVariables = {
    FCQEMU_NO_TTY = "true";
  };

}
