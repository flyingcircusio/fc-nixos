{ config, lib, ... }: {
  options = {
    flyingcircus.vmMemoryOverhead = lib.mkOption {
      default = 2304;
      type = lib.types.int;
      description = ''
        Memory overhead of the VM used for the system and operating system components.

        This is used to calculate memory for services to use.

        This is equivalent to https://doc.flyingcircus.io/platform/infrastructure/vms/index.html#minimum-memory-requirements-nixos-based-vms-only
        without the kernel structures as these are already subtracted from the memory available to the OS.
      '';
    };
  };

  config =
    let
      serviceMemoryOptions = {
        "opensearch" = {
          enablePath = [
            "flyingcircus"
            "roles"
            "opensearch"
            "enable"
          ];
          memoryPath = [
            "flyingcircus"
            "roles"
            "opensearch"
            "heapPercentage"
          ];
        };
        "percona84" = {
          enablePath = [
            "flyingcircus"
            "roles"
            "percona84"
            "enable"
          ];
          memoryPath = [
            "flyingcircus"
            "roles"
            "mysql"
            "bufferMemoryPercentage"
          ];
        };
        "redis" = {
          enablePath = [
            "flyingcircus"
            "roles"
            "redis"
            "enable"
          ];
          memoryPath = [
            "flyingcircus"
            "services"
            "redis"
            "memoryPercentage"
          ];
        };
        "webproxy" = {
          enablePath = [
            "flyingcircus"
            "roles"
            "webproxy"
            "enable"
          ];
          memoryPath = [
            "flyingcircus"
            "roles"
            "webproxy"
            "mallocMemoryPercentage"
          ];
        };
      }
      // lib.genAttrs [ "mariadb114" "mariadb118" ] (role: {
        enablePath = [
          "flyingcircus"
          "roles"
          role
          "enable"
        ];
        memoryPath = [
          "flyingcircus"
          "roles"
          "mariadb"
          "bufferMemoryPercentage"
        ];
      })
      // lib.genAttrs [ "elasticsearch6" "elasticsearch7" ] (role: {
        enablePath = [
          "flyingcircus"
          "roles"
          role
          "enable"
        ];
        memoryPath = [
          "flyingcircus"
          "roles"
          "elasticsearch"
          "heapPercentage"
        ];
      });
      activatedServices = lib.filterAttrs (
        name: paths: lib.getAttrFromPath paths.enablePath config
      ) serviceMemoryOptions;
      serviceMemoryValues = builtins.mapAttrs (
        name: paths:
        paths
        // {
          value = lib.getAttrFromPath paths.memoryPath config;
        }
      ) activatedServices;
    in
    {
      assertions = [
        {
          assertion =
            (builtins.foldl' (acc: elem: acc + elem) 0 (
              lib.mapAttrsToList (name: val: val.value) serviceMemoryValues
            )) <= 100;
          message = "Memory configured for services is more than VM allows. Configured values are ${
            lib.join ", " (
              lib.mapAttrsToList (
                name: val: "${name} (${toString val.value}% | ${lib.join "." val.memoryPath})"
              ) serviceMemoryValues
            )
          }";
        }
      ];
    };
}
