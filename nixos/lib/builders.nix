{ pkgs, lib }:

with builtins;

let
  shellDryRun = "${pkgs.stdenv.shell} -n -O extglob";
in {
  /*
    Similar to writeShellScriptBin and writeScriptBin.
    Writes an executable Shell script to /nix/store/<store path>/bin/<name> and
    checks its syntax with shellcheck and the shell's -n option.
    Individual checks can be foregone by putting them in the excludeShellChecks
    list, e.g. [ "SC2016" ].
    Automatically includes sane set of shellopts (errexit, nounset, pipefail)
    and handles creation of PATH based on runtimeInputs

    Note that the checkPhase uses stdenv.shell for the test run of the script,
    while the generated shebang uses runtimeShell. If, for whatever reason,
    those were to mismatch you might lose fidelity in the default checks.

    Example:

    Writes my-file to /nix/store/<store path>/bin/my-file and makes executable.


    writeShellApplication {
      name = "my-file";
      runtimeInputs = [ curl w3m ];
      text = ''
        curl -s 'https://nixos.org' | w3m -dump -T text/html
       '';
    }

  */
  writeShellApplication =
    { name
    , text
    , runtimeInputs ? [ ]
    , checkPhase ? null
    , excludeShellChecks ? [  ]
    }:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${pkgs.runtimeShell}
        set -o errexit
        set -o nounset
        set -o pipefail
      '' + lib.optionalString (runtimeInputs != [ ]) ''

        export PATH="${lib.makeBinPath runtimeInputs}:$PATH"
      '' + ''

        ${text}
      '';

      checkPhase =
        let
          excludeOption = lib.optionalString (excludeShellChecks != [ ]) "--exclude '${lib.concatStringsSep "," excludeShellChecks}'";
        in
        if checkPhase == null then ''
          target=$out/bin/${name}
          runHook preCheck
          ${shellDryRun} "$target"
          ${pkgs.shellcheck}/bin/shellcheck ${excludeOption} "$target"
          runHook postCheck
        ''
        else checkPhase;
    };

}
