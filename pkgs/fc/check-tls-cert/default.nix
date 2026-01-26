{
  lib,
  openssl,
  buildPythonApplication,
  pytestCheckHook,
  setuptools,
}:
buildPythonApplication {
  pname = "check-tls-cert";
  version = "1.0";
  pyproject = true;
  src = ./.;

  __structuredAttrs = true;

  build-system = [ setuptools ];

  nativeCheckInputs = [
    pytestCheckHook
  ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${lib.makeBinPath [ openssl ]}"
  ];

  preCheck = ''
    export PATH="${openssl}/bin:$PATH"
  '';

  meta = with lib; {
    description = "TLS certificate checker for monitoring";
    homepage = "https://github.com/flyingcircusio/fc-nixos";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
