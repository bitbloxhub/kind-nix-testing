{
  lib,
  self,
  ...
}:
{
  flake.modules.kubenix.default = {
    options.kustomization = {
      wait = lib.mkOption {
        type = lib.types.boolean;
        default = true;
      };
      dependsOn = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              namespace = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              readyExpr = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [
          {
            name = "flux-system";
          }
        ];
      };
      healthChecks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              apiVersion = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              kind = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              name = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              namespace = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };
      healthCheckExprs = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              apiVersion = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = null;
              };
              kind = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              current = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              inProgress = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              failed = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };
    };
  };

  flake.modules.kubenix.flux-system =
    {
      self',
      ...
    }:
    {
      config.kubernetes.resources.kustomizations = builtins.listToAttrs (
        builtins.map
          (name: {
            inherit name;
            value = {
              metadata.namespace = "flux-system";
              spec = {
                inherit (self'.packages.kustomization-sources.${name}.config.kustomization) dependsOn;
                inherit (self'.packages.kustomization-sources.${name}.config.kustomization) healthChecks;
                interval = "1m0s";
                path = "./${name}";
                prune = true;
                sourceRef = {
                  kind = "OCIRepository";
                  name = "flux-system";
                };
              };
            };
          })
          (
            builtins.filter (name: name != "default" && name != "flux-system") (
              builtins.attrNames self.modules.kubenix
            )
          )
      );
    };

  flake.modules.kubenix.flux-setup = {
    config.kubernetes.resources.fluxinstances.flux = {
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
          url = "oci://kind-nix-testing-registry:5000/kind-nix-testing-flux";
          ref = "latest";
          path = "./flux-system";
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
  };
}
