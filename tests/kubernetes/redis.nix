{ pkgs }:
with builtins;

rec {
  image = pkgs.dockerTools.buildImage {
    name = "redis";
    tag = "latest";
    contents = [ pkgs.redis ];
    config.Entrypoint = ["/bin/redis-server"];
  };

  podJson = toJSON {
    kind = "Pod";
    apiVersion = "v1";
    metadata.name = "redis";
    metadata.labels.name = "redis";
    spec.containers = [{
      name = "redis";
      image = "redis";
      args = ["--bind" "0.0.0.0"];
      imagePullPolicy = "Never";
      ports = [{
        name = "redis-server";
        containerPort = 6379;
      }];
    }];
  };

  serviceJson = toJSON {
    kind = "Service";
    apiVersion = "v1";
    metadata.name = "redis";
    spec = {
      ports = [{port = 6379; targetPort = 6379;}];
      selector = {name = "redis";};
    };
  };

  deploymentJson = toJSON {
    kind = "Deployment";
    apiVersion = "apps/v1";
    metadata = {
      name = "redis";
      labels = {
        name = "redis";
      };
    };
    spec = {
      replicas = 1;
      selector.matchLabels.name = "redis";
      template = {
        metadata.labels.name = "redis";
        spec = {
          containers = [{
            name = "redis";
            image = "redis";
            imagePullPolicy = "Never";
            ports = [ { containerPort = 6379; } ];
          }];
        };
      };
    };
  };

  deployment = pkgs.writeText "redis-deployment.json" deploymentJson;
  service = pkgs.writeText "redis-service.json" serviceJson;
  pod = pkgs.writeText "redis-pod.json" podJson;
}
