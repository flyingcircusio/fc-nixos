super:

python-self: python-super:
{

  pytoml = python-super.zodbpickle.overrideAttrs (old: rec {
    pname = "pytoml";
    version = "0.1.20";
    src = super.fetchFromGitHub {
      owner = "avakar";
      repo = "pytoml";
      rev = "v${version}";
      fetchSubmodules = true; # ensure test submodule is available
      sha256 = "02hjq44zhh6z0fsbm3hvz34sav6fic90sjrw8g1pkdvskzzl46mz";
    };
  });

  pyyaml = python-super.pyyaml.overrideAttrs (old: rec {
    pname = "PyYAML";
    version = "5.1.2";
    name = "${pname}-${version}";
    src = python-super.fetchPypi {
      inherit pname version;
      sha256 = "01adf0b6c6f61bd11af6e10ca52b7d4057dd0be0343eb9283c878cf3af56aee4";
    };
  });

  zodbpickle = python-super.zodbpickle.overrideAttrs (old: rec {
    pname = "zodbpickle";
    version = "2.0.0";
    name = "${pname}-${version}";
    src = python-super.fetchPypi {
      inherit pname version;
      sha256 = "0fb7c7pnz86pcs6qqwlyw72vnijc04ns2h1zfrm0h7yl8q7r7ng0";
    };
  });

  nagiosplugin = python-super.buildPythonPackage rec {
    pname = "nagiosplugin";
    version = "1.2.4";
    src = python-super.fetchPypi {
      inherit pname version;
      sha256 = "1fzq6mhwrlz1nbcp8f7sg3rnnaghhb9nd21p0anl6dkga750l0kb";
    };

    # "cannot determine number of users (who failed)"
    preCheck = ''
      substituteInPlace src/nagiosplugin/tests/test_examples.py \
        --replace "test_check_users" "_disabled"
    '';

    dontStrip = true;
  };
}
