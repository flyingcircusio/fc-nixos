{ config, lib, ... }:

let
  fclib = config.fclib;
in

with lib;

rec {

  # Get all regular files and symlinks with their name relative to path
  filesRel = path:
    optionals
      (pathExists path)
      (attrNames
        (filterAttrs
          (filename: type: (type == "regular" || type == "symlink"))
          (builtins.readDir path)));

  # Get all regular files and symlinks with their absolute name
  files = path:
    (map
      (filename: path + ("/" + filename))
      (filesRel path));

  # Reads the config file if it exists, else returns predefined default
  configFromFile = file: default:
    if pathExists file then readFile file else default;

  jsonFromFile = file: default:
    builtins.fromJSON (configFromFile file default);

  # Reads JSON config snippets from a directory and merges them into one object.
  # Each snippet must contain a single top-level object.
  # The keys in the top-level objects must be unique for all snippets.
  # Throws an error if duplicate keys are found.
  jsonFromDir = path: let
    objects =
      map
        (filename: builtins.fromJSON (readFile filename))
        (filter
          (filename: hasSuffix "json" filename)
          (files path));

    mergedObject =
      fold
        (obj: acc: acc // obj)
        {}
        objects;

    duplicates = fclib.duplicateAttrNames objects;
  in
    if duplicates == []
    then mergedObject
    else throw ''
      Top-level JSON config keys are not unique in ${path}!
      Duplicate keys: ${concatStringsSep ", " duplicates}
    ''
  ;
}
