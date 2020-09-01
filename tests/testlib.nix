{ lib }:
{
  derivePasswordForHost = prefix:
    builtins.hashString "sha256" (lib.concatStringsSep "/" [
      prefix
      ""
      "machine"
    ]);

    # Returns Sensu check command by name.
    # Newlines in the command are removed to avoid breaking the test script.
    sensuCheckCmd = machine: checkName:
      lib.replaceStrings
        ["\\" "\n"]
        ["" " "]
        machine.config.flyingcircus.services.sensu-client.checks.${checkName}.command;
}
