import ./make-test-python.nix (
  { ... }:
  {
    name = "nixversions";
    nodes =
      let
        mkTestVM =
          {
            location,
            withSlurm ? false,
            production ? true,
          }:
          { lib, pkgs, ... }:
          {
            imports = [
              ../nixos
              ../nixos/roles
            ];
            flyingcircus.agent.package = lib.mkIf withSlurm pkgs.fc.agentWithSlurm;
            flyingcircus.enc.parameters = {
              inherit location production;
              resource_group = "test";
              interfaces.srv = {
                mac = "52:54:00:12:34:56";
                bridged = false;
                networks = {
                  "192.168.101.0/24" = [ "192.168.101.7" ];
                  "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::7" ];
                };
                gateways = { };
              };
            };
          };
      in
      {
        production = mkTestVM { location = "rzob"; };
        nonProd = mkTestVM {
          location = "rzob";
          production = false;
        };
        slurmOnProduction = mkTestVM {
          location = "rzob";
          withSlurm = true;
        };
        slurmOnNonProd = mkTestVM {
          location = "rzob";
          withSlurm = true;
          production = false;
        };

        devVM = mkTestVM { location = "dev"; };
        devVMNonProd = mkTestVM {
          location = "dev";
          production = false;
        };
        whqVM = mkTestVM { location = "whq"; };
        whqVMNonProd = mkTestVM {
          location = "whq";
          production = false;
        };
      };

    testScript = ''
      import os.path
      import re

      relevant_nix_versions = [
        # the default on production
        "2.25",
        # default Nix in 25.05
        "2.24",
        # the default on staging
        "2.25",
      ]

      def strip_hash(store_path):
          basename = os.path.basename(store_path)
          return basename.split("-", 1)[1]

      def verify_nix_versions(vm, expected_nix="2.25", expect_slurm=False):
          vm.start()
          version = vm.succeed("nix --version")
          assert version.startswith(f"nix (Nix) {expected_nix}."), f"""
            Expected Nix version to start with
              nix (Nix) {expected_nix}.
            Full output:
              {version}
          """
          nix = os.path.dirname(os.path.dirname(vm.succeed("readlink -f $(type -P nix)")))
          fc_agent = vm.succeed("readlink -f $(type -P fc-manage)")

          # no `nix why-depends` here since it always gives 0 as exit code and we'd have to
          # match the stderr.
          agent_closure = vm.succeed(f"nix-store -qR {fc_agent}").rstrip("\n").split("\n")
          assert nix in agent_closure, f"""
            Expected Nix {expected_nix} (i.e. store-path {nix}) to be in
            the agent closure:

            {agent_closure}
          """

          nix_versions_not_used = [x for x in relevant_nix_versions if x != expected_nix]
          assert all(
              not strip_hash(p).startswith(f"nix-{majorminor}.")
              for p in agent_closure
              for majorminor in nix_versions_not_used
          ), f"""
            Expected Nix versions {", ".join(nix_versions_not_used)} to NOT be in the agent closure:

            {agent_closure}
          """

          assert any(strip_hash(p).startswith("slurm-") for p in agent_closure) == expect_slurm, """
            Expected no `slurm` in agent closure:

            {agent_closure}
          """

          vm.shutdown()


      with subtest("rzob production vm"):
          verify_nix_versions(production, "2.25")

      with subtest("rzob non-prod vm"):
          verify_nix_versions(nonProd, "2.25")

      with subtest("rzob prod vm with slurm"):
          verify_nix_versions(slurmOnProduction, "2.25", expect_slurm=True)

      with subtest("rzob non-prod vm with slurm"):
          verify_nix_versions(slurmOnNonProd, "2.25", expect_slurm=True)

      with subtest("whq vm"):
          verify_nix_versions(whqVM, "2.25")

      with subtest("whq vm with non-prod flag"):
          verify_nix_versions(whqVMNonProd, "2.25")

      with subtest("dev vm prod"):
          verify_nix_versions(devVM, "2.25")

      with subtest("dev vm non-prod"):
          verify_nix_versions(devVMNonProd, "2.25")
    '';
  }
)
