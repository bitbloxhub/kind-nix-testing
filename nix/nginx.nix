{
  lib,
  inputs,
  ...
}:
{
  flake.modules.kubenix.default = {
    kubernetes.resources.pods.nginx = {
      metadata.namespace = "default";
      spec.containers = [
        {
          name = "nginx";
          image = "nginx:1.29.1";
          ports = [
            {
              containerPort = 80;
              protocol = "TCP";
            }
          ];
        }
      ];
    };
  };
}
