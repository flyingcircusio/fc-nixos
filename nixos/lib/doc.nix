# Utilities for documentation strings/files.
{ lib, options, ...}:

with builtins;

rec {
  docList = list:
    "[ ${lib.concatMapStringsSep " " (n: ''"${n}"'') list} ]";

  docOption = name:
    let
      optPath = lib.splitString "." name;
      opt = lib.getAttrFromPath optPath options;
      description =
        if isAttrs opt.description
        then opt.description.text
        else opt.description;
    in
    trace (toJSON { inherit opt optPath; inherit description; })
    lib.concatStringsSep "\n\n" [
      "**${name}**"
      (lib.removePrefix "\n" (lib.removeSuffix "\n" description))
    ];
}
