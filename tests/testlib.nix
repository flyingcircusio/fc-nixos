{ lib }:
{ 
  derivePasswordForHost = prefix:
    builtins.hashString "sha256" (lib.concatStringsSep "/" [
      prefix
      ""
      "machine"
    ]);
}
