{
  config,
  lib,
  pkgs,
  ...
}:

# This file needs to be kept (somewhat) in sync with our
# `ceph-nautilus.nix` in the platform.
let
  fclib = config.fclib;
  testPackage = config.flyingcircus.services.ceph.fc-ceph.package;
in
{

  environment.systemPackages =
    # This is a horrible dance for two reasons:
    # 1. pytest doesn't properly inherit the PATH environment from the propagatedBuildInputs.
    #    We might want to reconsider using an additional buildPythonApplication with pytest
    #    added to the primary dependencies (propagatedBuildInputs)
    # 2. There's a bug(?) in stdenv.mkDerivation that causes external access to the
    #    attribute's items to end up with their .dev outputs ... -_-
    let
      testPackages = (
        [ testPackage ]
        ++ (map (x: builtins.removeAttrs x [ "outputSpecified" ]) testPackage.propagatedBuildInputs)
        ++ testPackage.nativeCheckInputs
      );
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
