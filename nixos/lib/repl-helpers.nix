{ lib, pkgs, ... }:

with builtins;

let
  printEtcFile = config: name:
  let
    value = config.environment.etc.${name};
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

in {
  inherit format print printEtcFile;
}
