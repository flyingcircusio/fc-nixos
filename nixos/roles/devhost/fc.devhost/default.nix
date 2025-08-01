{
  lib,
  python3,
  qemu,
  xfsprogs,
  ...
}:

python3.pkgs.buildPythonApplication {
  pname = "fc-devhost";
  version = "1.0.0";

  src = ./.;
  pyproject = true;
  build-system = with python3.pkgs; [ setuptools ];
  dependencies = with python3.pkgs; [
    psutil
    requests
    tabulate
  ];
  propagatedBuildInputs = [
    qemu
    xfsprogs
  ];
  meta = {
    mainProgram = "fc-devhost";
    license = lib.licenses.mit;
  };
}
