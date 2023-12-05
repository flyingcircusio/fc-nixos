# This is just a stub to check if nodejs packages can display their version.
# The test makes sure that the nodejs packages we want still exist and are
# built by our hydra or are available upstream.
import ./make-test-python.nix ({ pkgs, testlib, ... }:
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
      "${nodejs_18}": "18",
      "${nodejs_20}": "20",
      "${nodejs_21}": "21",
      "${nodejs-slim_18}": "18",
      "${nodejs-slim}": "18",
      "${nodejs}": "18",
      "${nodejs-slim_20}": "20",
      "${nodejs-slim_21}": "21",
    }

    for package, version in package_versions.items():
      with subtest(f"Checking package {package}"):
        out = machine.succeed(f"{package}/bin/node -v").strip()
        expected = f"v{version}."
        assert out.startswith(expected), (
          "version must start with {expected}, got: " + out
        )
  '';
})
