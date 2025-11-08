{
  flake.modules.kubenix.headlamp = {
    kubernetes.resources.namespaces.headlamp = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "headlamp";
    };

    kubernetes.resources.helmrepositories.headlamp = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1h0s";
        url = "https://kubernetes-sigs.github.io/headlamp/";
      };
    };

    kubernetes.resources.helmreleases.headlamp = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        chart.spec = {
          chart = "headlamp";
          version = "0.37.0";
          sourceRef = {
            kind = "HelmRepository";
            name = "headlamp";
          };
        };
        values.namespaceOverride = "headlamp";
      };
    };
  };
}
