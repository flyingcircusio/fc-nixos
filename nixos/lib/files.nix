{ lib, ... }:

with lib;

rec {

  # Get all regular files with their name relative to path
  filesRel = path:
    optionals
      (pathExists path)
      (attrNames
        (filterAttrs
          (filename: type: (type == "regular"))
          (builtins.readDir path)));

  # Get all regular files with their absolute name
  files = path:
    (map
      (filename: path + ("/" + filename))
      (filesRel path));

  # Reads the config file if it exists, else returns predefined default
  configFromFile = file: default:
    if pathExists file then readFile file else default;

  jsonFromFile = file: default:
    builtins.fromJSON (configFromFile file default);

}
