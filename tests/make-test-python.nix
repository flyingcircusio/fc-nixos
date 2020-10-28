# Make a test using Python test scripts, possibly with multiple test cases.
# f can be a set or a function returning a set.
# A single test case is defined by a name, test script and machine / nodes specification.
# Multiple test cases can be defined in a set called 'testCases'.
# When multiple cases are defined, the name attribute is used as prefix for the test case names.
#
# Single test case:
#
# import ./make-test.nix ({ ... }:
# {
#   name = "test";
#   machine = ...
#   testScript = ...
# })
#
# This creates a single case called 'test'.
#
# Multiple:
#
# import ./make-test.nix ({ ... }:
# {
#   name = "test";
#   testCases = {
#     case1 = {
#       machine = ...
#       testScript = ...
#     };
#     case2 = {
#       nodes = ...
#       testScript = ...
#     };
#   };
# })
#
# This will create two test cases called 'test-case1' and 'test-case2'.

f: {
  system ? builtins.currentSystem
  , nixpkgs ? (import ../versions.nix {}).nixpkgs
  , pkgs ? import ../. { inherit nixpkgs; }
  , minimal ? false
  , config ? {}
  , ...
} @ args:

with import "${nixpkgs}/nixos/lib/testing-python.nix" {
  inherit system pkgs;
};

let
  lib = pkgs.lib;
  test =
    if lib.isFunction f
    then f (args // {
      inherit pkgs lib;
      testlib = pkgs.callPackage ./testlib.nix {};
    })
    else f;

  makeTestSkipLint = args: makeTest ({ skipLint = true; } // args);

in if test ? testCases
then lib.mapAttrs
  (testCaseName: testCase: makeTestSkipLint (
    testCase // { name = "${test.name}-${testCaseName}"; }))
  test.testCases
else makeTestSkipLint test
