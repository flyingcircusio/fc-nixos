# This is just a stub to check if nodejs packages can display their version.
# The test makes sure that the nodejs packages we want still exist and are
# built by our hydra or are available upstream.
import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  {
    name = "nodejs";

    nodes.machine =
      { pkgs, config, ... }:
      {
        imports = [
          (testlib.fcConfig { })
        ];
      };

    testScript = with pkgs; ''
      package_versions = {
        "${nodejs-slim_22}": "22",
        "${nodejs-slim_24}": "24",
        "${nodejs-slim}": "24",
        "${nodejs_22}": "22",
        "${nodejs_24}": "24",
        "${nodejs}": "24",
      }

      for package, version in package_versions.items():
        with subtest(f"Checking package {package}"):
          out = machine.succeed(f"{package}/bin/node -v").strip()
          expected = f"v{version}."
          assert out.startswith(expected), (
            f"version must start with {expected}, got: " + out
          )
    '';
  }
)
