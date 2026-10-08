import ./make-test-python.nix (
  {
    testlib,
    pkgs,
    ...
  }:
  let
    v4 = (testlib.fcIP.srv4 1);
    v6 = (testlib.fcIP.srv6 1);

    traceGenerator = pkgs.writeScriptBin "trace-generator" ''
      #!${
        pkgs.python3.withPackages (
          ps: with ps; [
            requests
            protobuf
            opentelemetry-proto
            opentelemetry-api
            opentelemetry-sdk
            opentelemetry-exporter-otlp-proto-http
          ]
        )
      }/bin/python3

      import time
      from opentelemetry import trace
      from opentelemetry.sdk.trace import TracerProvider
      from opentelemetry.sdk.trace.export import BatchSpanProcessor
      from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
      from opentelemetry.sdk.resources import Resource

      resource = Resource.create({
          "service.name": "test-service",
          "service.version": "1.0.0"
      })

      provider = TracerProvider(resource=resource)

      otlp_exporter = OTLPSpanExporter(
          endpoint="http://${v4}:4320/v1/traces",
          headers={},
      )

      provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
      trace.set_tracer_provider(provider)

      tracer = trace.get_tracer("test-tracer", "1.0.0")

      # Test span
      with tracer.start_as_current_span("test-span") as span:
          span.set_attribute("http.method", "GET")
          span.set_attribute("http.url", "/test")
          time.sleep(0.1)

      provider.force_flush()

      print("Test trace sent")
    '';
  in
  {
    name = "tempo";

    nodes.machine = { lib, pkgs, ... }: {
      imports = [
        ../nixos
        ../nixos/roles
        (testlib.fcConfig { net.fe = true; })
      ];

      flyingcircus.roles.statshost-master.enable = true;
      flyingcircus.roles.statshost = {
        hostName = "myself";
        useSSL = false;
      };

      # enable statshost role for prometheus only, no need for nginx or grafana
      services.grafana.enable = lib.mkForce false;
      services.nginx.enable = lib.mkForce false;
      flyingcircus.services.nginx.enable = lib.mkForce false;
      systemd.services.fc-grafana-load-dashboards.enable = false;

      flyingcircus.roles = {
        tempo = {
          enable = true;
          s3.enable = false;
        };
        loki = {
          enable = true;
          storageSchedule.default = lib.mkForce [
            {
              startDate = "2024-09-10";
              backend = "filesystem";
            }
          ];
        };
      };

      # TODO add this to the role for when s3 is disabled
      services.tempo.settings.storage.trace.backend = "local";
      services.tempo.settings.storage.trace.local.path = "/var/tempo/trace/";

      flyingcircus.encServices =
        builtins.map
          (service: {
            address = v4;
            inherit service;
            ips = [
              v4
              v6
            ];
          })
          [
            "loki-collector"
            "tempo-collector"
            "statshost-master-collector"
          ];

      environment.systemPackages = [
        traceGenerator
        pkgs.curl
        pkgs.jq
      ];
    };

    testScript = ''
      machine.wait_for_unit("tempo.service")
      machine.wait_for_unit("alloy.service")
      machine.wait_for_unit("loki.service")
      machine.wait_for_unit("prometheus.service")
      machine.wait_for_open_port(port=4320, addr="${v4}")

      machine.succeed("trace-generator")
      machine.sleep(10)
      machine.succeed("test $(curl -G -s http://localhost:3200/api/search --data-urlencode 'q={ resource.service.name = \"test-service\" }' | jq '.traces | length') -gt 0")
    '';
  }
)
