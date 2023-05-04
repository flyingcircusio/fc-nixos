# Utilities for documentation strings/files.
{ lib, config, options, ...}:

with builtins;

rec {
  docList = list:
    "[ ${lib.concatMapStringsSep " " (n: ''"${n}"'') list} ]";

  roleDocUrl = name:
  let
    inherit (config.flyingcircus.platform) editions;
    encEnv =
      lib.attrByPath
        [ "parameters" "environment" ]
        "unknown"
        config.flyingcircus.enc;
    environment =
      if (elem encEnv editions) then encEnv
      else head editions;

  in
    "https://doc.flyingcircus.io/roles/${environment}/${name}.html";

  docOption = name:
    let
      optPath = lib.splitString "." name;
      opt = lib.getAttrFromPath optPath options;
      description =
        if isAttrs opt.description
        then opt.description.text
        else opt.description;
    in
    lib.concatStringsSep "\n\n" [
      "**${name}**"
      (lib.removePrefix "\n" (lib.removeSuffix "\n" description))
    ];
}
