{
  lib,
  ceph-client,
  buildPythonApplication,
  setuptools,
  nagiosplugin,
  pytestCheckHook,
}:

buildPythonApplication rec {
  name = "fc-check-ceph-nautilus-${version}";
  version = "1.0";
  src = ./.;
  dontStrip = true;
  pyproject = true;
  __structuredAttrs = true;

  build-system = [
    setuptools
  ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${lib.makeBinPath [ ceph-client ]}"
  ];

  dependencies = [
    nagiosplugin
  ];

  nativeCheckInputs = [
    pytestCheckHook
  ];
}
