{
  poetry2nix,
  fetchFromGitHub,
  lzo,
  python310
}:
let
  #src = /home/os/backy;
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "93b18b09b3db1cba4a10c6613bfec0ad0d82895a";
    hash = "sha256-HRndYUW08c8ncxwGdSOZWyXszzJ0JDKBAlFSS+UiQRU=";
  };

in poetry2nix.mkPoetryApplication {
    projectDir = src;
    src = src;
    doCheck = true;
    python = python310;
    extras = [];
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      python-lzo = super.python-lzo.overrideAttrs (old: {
        buildInputs = [ lzo ];
      });
      telnetlib3 = super.telnetlib3.overrideAttrs (old: {
        buildInputs = [ super.setuptools ];
      });
      pytest-flake8 = super.pytest-flake8.overrideAttrs (old: {
        buildInputs = [ super.setuptools ];
      });
      filelock = super.iniconfig.overrideAttrs (old: {
        buildInputs = [ super.hatchling super.hatch-vcs ];
      });
      iniconfig = super.iniconfig.overrideAttrs (old: {
        buildInputs = [ super.hatchling super.hatch-vcs ];
      });
      humanize = super.humanize.overrideAttrs (old: {
        buildInputs = [ super.hatchling super.hatch-vcs ];
      });
      prettytable = super.prettytable.overrideAttrs (old: {
        buildInputs = [ super.hatchling super.hatch-vcs ];
      });
      # dirty workaround, as the virtualenv-20.17.1 extracted via poetry2nix did not
      # find its `filelock` dependency
      virtualenv = python310.pkgs.virtualenv;
      #virtualenv = super.virtualenv.overrideAttrs (old: {
      #  buildInputs = [ self.distlib self.filelock self.platformdirs ];
      #});
      consulate-fc-nix-test = super.consulate-fc-nix-test.overrideAttrs (old: {
        buildInputs = [ super.setuptools super.setuptools-scm ];
      });
    });
}
