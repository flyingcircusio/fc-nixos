{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "aramaki-monitoring";
  version = "unstable-2025-08-13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "aramaki.monitoring";
    rev = "461f7ec2adc05c5caa35d325c63f5ab0b8fd8726";
    hash = "sha256-JNw3g5LpLx7q8ilWvJyeMKCf/xdnGOSUm1b2YjA/OSQ=";
  };

  build-system = [
    python3.pkgs.hatchling
  ];

  dependencies = with python3.pkgs; [
    rfc8785
    structlog
    websockets
  ];

  pythonImportsCheck = [
    "aramaki_monitoring"
  ];

  meta = {
    description = "A monitoring client based on Aramaki";
    homepage = "https://github.com/flyingcircusio/aramaki.monitoring";
    mainProgram = "aramaki-monitoring";
  };
}
