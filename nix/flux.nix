{
  lib,
  inputs,
  ...
}:
{
  flake.modules.kubenix.default = {
    kubernetes.resources.fluxinstances.flux = {
      metadata.namespace = "flux-system";
      metadata.annotations = {
        "fluxcd.controlplane.io/reconcileEvery" = "1m";
        "fluxcd.controlplane.io/reconcileTimeout" = "5m";
        apply-order = "10";
      };
      spec = {
        distribution = {
          registry = "ghcr.io/fluxcd";
          version = "2.7.3";
        };
        sync = {
          kind = "OCIRepository";
          url = "oci://kind-nix-testing-registry:5000/kind-nix-testing-flux-infra";
          ref = "latest";
          path = ".";
        };
        kustomize.patches = [
          {
            patch = ''
              - op: add
                path: /spec/insecure
                value: true
            '';
            target = {
              kind = "(OCIRepository|Bucket)";
            };
          }
        ];
      };
    };

    kubernetes.resources.kustomizations.infra = {
      metadata.namespace = "flux-system";
      metadata.annotations.apply-order = "100";
      spec = {
        interval = "1m0s";
        path = "./";
        wait = true;
        prune = true;
        sourceRef = {
          kind = "OCIRepository";
          name = "flux-system";
        };
      };
    };

    kubernetes.resources.ocirepositories.apps = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        insecure = true;
        url = "oci://kind-nix-testing-registry:5000/kind-nix-testing-flux-apps";
        ref.tag = "latest";
      };
    };

    kubernetes.resources.kustomizations.apps = {
      metadata.namespace = "flux-system";
      spec = {
        dependsOn = [ {
          name = "infra";
          readyExpr = ''
            dep.status.conditions.exists(condition, condition.type == "Healthy") ||
            dep.status.conditions.exists(condition, condition.message.contains("timeout waiting for: [Kustomization/flux-system/apps status: 'InProgress']"))
          '';
        } ];
        interval = "1m0s";
        path = "./";
        prune = true;
        sourceRef = {
          kind = "OCIRepository";
          name = "apps";
        };
      };
    };
  };
}
