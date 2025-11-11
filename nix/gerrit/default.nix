{
  inputs,
  ...
}:
{
  flake.modules.kubenix.gerrit-operator = {
    kubernetes.resources.namespaces.gerrit-operator = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "gerrit-operator";
    };

    kubernetes.resources.gitrepositories.gerrit-operator = {
      metadata.namespace = "flux-system";
      metadata.annotations = {
        apply-order = "100";
      };
      spec = {
        interval = "1h0s";
        url = "https://github.com/bitbloxhub/k8s-gerrit";
        ref.commit = "9772a1389af5e3e9bb53f8a8a842f232f129f3f0";
      };
    };

    kubernetes.resources.helmcharts.gerrit-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        chart = "./helm-charts/gerrit-operator";
        sourceRef = {
          kind = "GitRepository";
          name = "gerrit-operator";
        };
      };
    };

    kubernetes.resources.helmreleases.gerrit-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        chartRef = {
          kind = "HelmChart";
          name = "gerrit-operator";
        };
        targetNamespace = "gerrit-operator";
        values = {
          installCRDs = true;
          image.tag = "v0.1-799-g397fda38";
        };
      };
    };
  };

  flake.modules.kubenix.gerrit = {
    kustomization.dependsOn = [
      {
        name = "gerrit-operator";
      }
    ];

    kubernetes.resources.namespaces.gerrit = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "gerrit";
    };

    kubernetes.resources.secrets.gerrit-secure-config = {
      metadata.namespace = "gerrit";
      type = "Opaque";
      data = {
        ssh_host_ecdsa_key = inputs.nix-base64.lib.toBase64 (builtins.readFile ./ssh_host_ecdsa_key);
        "ssh_host_ecdsa_key.pub" = inputs.nix-base64.lib.toBase64 (builtins.readFile ./ssh_host_ecdsa_key.pub);
      };
    };

    kubernetes.resources.gerritclusters.gerrit = {
      metadata.namespace = "gerrit";
      spec = {
        containerImages.imagePullPolicy = "IfNotPresent";
        storage = {
          storageClasses = {
            readWriteOnce = "standard";
            readWriteMany = "standard";
          };
          sharedStorage.size = "10Gi";
        };
        ingress.enabled = false;
        serverId = "gerrit";
        gerrits = [
          {
            metadata.name = "gerrit";
            spec = {
              mode = "PRIMARY";
              replicas = 1;
              resources = {
                requests = {
                  cpu = 1;
                  memory = "8Gi";
                };
                limits = {
                  cpu = 1;
                  memory = "9Gi";
                };
              };
              service.type = "ClusterIP";
              site.size = "10Gi";
              configFiles."gerrit.config" = builtins.readFile ./gerrit.config;
              secretRef = "gerrit-secure-config";
            };
          }
        ];
      };
    };
  };
}
