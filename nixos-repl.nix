# A simple helper to make it easier to interactively explore the NixOS system.
# You have to run it as root because normal users are not allowed
# to evaluate the system, yet:
# sudo nix repl nixos-repl.nix
# System config, nixpkgs changes and the script itself can be reloaded from
# inside the repl with the `:r` command.
# `print` is a wrapper around builtins.trace that tries to
# pretty-print various types of Nix values. It outputs a hash of the
# printed string representation to be able to quickly spot if the output has
# changed between runs.
#
# Config attributes are at the top-level, so you can, for example,
# show effective postgresql settings with:
#   print services.postgresql.settings
# There's also the options attrset which you can use to find the files
# where an option is defined:
#   print options.services.postgresql.settings.files

with builtins;
let
  pkgs = import <nixpkgs> {};
  nixos = import <nixpkgs/nixos> {};
  inherit (nixos) options;

  etc = name:
  let
    value = options.environment.etc.value.${name};
    content =
      if value.text != null then
        print value.text
      else
        print (readFile value.source);
  in content;

  format = v:
  let
     json = toJSON v;
     out = pkgs.runCommandLocal "json" {} ''
      ${pkgs.jq}/bin/jq . <<< '${json}' > $out
    '';
  in
   if (v._type or "" == "option") then
     format v.value
   else if (isAttrs v || isList v) then
     readFile out
   else
     v;

  print = v:
  let
    formatted = format v;
  in
    trace formatted
      (if isString formatted
      then "output hash: " + (hashString "sha256" formatted)
      else 0);


in builtins // nixos.config // {
  inherit pkgs etc format print;
  inherit (pkgs) lib;
  inherit (nixos) config options;
}
