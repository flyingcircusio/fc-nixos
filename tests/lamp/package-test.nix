{ version ? "lamp_php74", pkgs ? import ./../.. {}, ... }:
let
  php = pkgs.${version};
  pcreTestPackage = import ./pcre-test-package.nix { pkgs = pkgs; php = php; };
in
{
  test = pkgs.runCommand "php-pcre-test-${version}" {} ''
    set -eo pipefail

    # run ${pcreTestPackage}/testPcre.sh and save output as variable
    output=$(${pcreTestPackage}/testPcre.sh)

    # remove the first line of the output, which just roughly shows the command that was run
    output=$(echo "''${output}" | tail -n +2)

    # if output contains "doesnotwork", exit with error
    if echo "$output" | grep "doesnotwork"; then
      echo "PCRE test failed with output: $output"
      exit 1
    fi
    >$out
  '';
}
