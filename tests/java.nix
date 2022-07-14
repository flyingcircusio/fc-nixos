import ./make-test-python.nix ({ pkgs, testlib, ... }:
{
  name = "java";

  nodes = {
    machine =
      { pkgs, config, ... }:
      {
        imports = [
          (testlib.fcConfig { })
        ];
      };
    };

  testScript = ''
    start_all()

    patched_zlib = "${pkgs.zlibCrcInputFix}"

    jdk = "${pkgs.jdk}"
    jdk11 = "${pkgs.jdk11}"
    jdk11_headless = "${pkgs.jdk11_headless}"
    jdk17 = "${pkgs.jdk17}"
    jdk17_headless = "${pkgs.jdk17_headless}"
    jdk8 = "${pkgs.jdk8}"
    jdk8_headless = "${pkgs.jdk8_headless}"
    jre = "${pkgs.jre}"
    jre8 = "${pkgs.jre8}"
    jre8_headless = "${pkgs.jre8_headless}"
    jre_headless = "${pkgs.jre_headless}"
    openjdk = "${pkgs.openjdk}"
    openjdk11 = "${pkgs.openjdk11}"
    openjdk11_headless = "${pkgs.openjdk11_headless}"
    openjdk17 = "${pkgs.openjdk17}"
    openjdk17_headless = "${pkgs.openjdk17_headless}"
    openjdk8 = "${pkgs.openjdk8}"
    openjdk8_headless = "${pkgs.openjdk8_headless}"

    with subtest("Package aliases for Java 8 should point to the same package"):
      assert openjdk8 == jdk8

    with subtest("Package aliases for Java 8 headless should point to the same package"):
      assert openjdk8_headless == jdk8_headless

    with subtest("Package aliases for Java 11 should point to the same package"):
      assert openjdk11 == jdk11

    with subtest("Package aliases for Java 11 headless should point to the same package"):
      assert openjdk11_headless == jdk11_headless

    with subtest("Package aliases for Java 17 should point to the same package"):
      assert jre == jdk
      assert jdk == openjdk
      assert openjdk == jdk17
      assert jdk17 == openjdk17

    with subtest("Package aliases for Java 17 headless should point to the same package"):
      assert jre_headless == jdk17_headless
      assert jdk17_headless == openjdk17_headless

    package_versions = {
      jdk8: "1.8",
      jdk8_headless: "1.8",
      jre8: "1.8",
      jre8_headless: "1.8",
      jdk11: "11",
      jdk11_headless: "11",
      openjdk17: "17",
    }

    print(f"Patched zlib: {patched_zlib}")

    for package, version in package_versions.items():
      with subtest(f"Checking java version in {package}"):
        out = machine.succeed(f"{package}/bin/java -version 2>&1")
        assert f"openjdk version \"{version}." in out

      with subtest(f"{package} should use patched zlib"):
        machine.succeed(f"grep {patched_zlib} {package}/bin/java")
  '';
})
