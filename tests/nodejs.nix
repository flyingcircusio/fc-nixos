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
      "${nodejs-14_x}": "14",
      "${nodejs-16_x}": "16",
      "${nodejs-18_x}": "18",
    }

    for package, version in package_versions.items():
      with subtest(f"Checking package {package}"):
        out = machine.succeed(f"{package}/bin/node -v").strip()
        assert out.startswith(f"v{version}."), "unexpected version: " + out
  '';
})
