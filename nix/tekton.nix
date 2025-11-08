{
  flake.modules.kubenix.tekton = {
    kubernetes.resources.gitrepositories.tekton-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1h0s";
        url = "https://github.com/tektoncd/operator";
        ref.tag = "v0.77.0";
      };
    };

    kubernetes.resources.helmcharts.tekton-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        chart = "./charts/tekton-operator";
        sourceRef = {
          name = "tekton-operator";
          kind = "GitRepository";
        };
      };
    };

    kubernetes.resources.helmreleases.tekton-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        chartRef = {
          kind = "HelmChart";
          name = "tekton-operator";
        };
        values.installCRDs = true;
        values.controllers = "tektonconfig,tektonpipeline,tektonresult";
      };
    };
  };
}
