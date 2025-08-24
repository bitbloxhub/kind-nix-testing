{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    kubenix.url = "github:hall/kubenix";
    kubenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        {
          packages.flux-operator-setup = pkgs.runCommand "flux-operator-setup" { } ''
            ${pkgs.yq-go}/bin/yq eval-all '[.] | filter(.kind == "FluxInstance") | .[] | splitDoc' ${self'.packages.kubernetes} > $out
          '';
          packages.flux-resources = pkgs.runCommand "flux-resources" { } ''
            ${pkgs.yq-go}/bin/yq eval-all '[.] | filter(.metadata.namespace == "flux-system") | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${self'.packages.kubernetes} > $out
          '';
          packages.kubernetes =
            (inputs.kubenix.evalModules.${system} {
              module =
                { kubenix, lib, ... }:
                let
                  allCrdResources = (
                    builtins.filter (manifest: manifest != null && (manifest.kind == "CustomResourceDefinition")) (
                      lib.flatten (
                        builtins.map
                          (
                            manifest:
                            lib.importJSON (
                              pkgs.runCommand "yaml-to-json" { } ''
                                ${pkgs.yq}/bin/yq -c . ${manifest} > out
                                sed -e 's/$/,/' -i out
                                sed '$ s/.$//' -i out
                                echo "[$(cat out)]" > $out
                              ''
                            )
                          )
                          [
                            (pkgs.fetchurl {
                              url = "https://github.com/fluxcd/flux2/releases/download/v2.6.4/install.yaml";
                              hash = "sha256-fNBDqCNmZye0ud5Ag0YUiyh0G0frCz5CN6tyWdStOrg=";
                            })
                            (pkgs.fetchurl {
                              url = "https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.28.0/install.yaml";
                              hash = "sha256-O9nnOVBYF89bpP+x6VWHeG0FVQIrlzIovOOe0y4UeRQ=";
                            })
                            (pkgs.fetchurl {
                              url = "https://github.com/tektoncd/pipeline/releases/download/v1.3.1/release.yaml";
                              hash = "sha256-2YW1h5qOrDMBeY/Md4DDQue8/l6i5hJ0dcuhCupWKT0=";
                            })
                            (pkgs.fetchurl {
                              url = "https://github.com/tektoncd/operator/releases/download/v0.77.0/release.yaml";
                              hash = "sha256-S5rYz8dw3WIFAlPDPzZU3o3LV2qLIeMRGf5N4773ltQ=";
                            })
                          ]
                      )
                    )
                  );
                  schemasFlattened =
                    let
                      processCrdVersion = crd: version: {
                        group = crd.spec.group;
                        version = version.name;
                        kind = crd.spec.names.kind;
                        attrName = crd.spec.names.plural;
                        fqdn = "${crd.spec.group}.${version.name}.${crd.spec.names.kind}";
                        schema = version.schema.openAPIV3Schema;
                      };
                      processCrd = crd: builtins.map (v: processCrdVersion crd v) crd.spec.versions;
                    in
                    builtins.concatMap processCrd allCrdResources;

                  allCrdsOpenApiDefinition = pkgs.writeTextFile {
                    name = "generated-kubenix-crds-schema.json";
                    text = builtins.toJSON {
                      definitions = builtins.listToAttrs (
                        builtins.map (x: {
                          name = x.fqdn;
                          value = x.schema;
                        }) schemasFlattened
                      );
                      paths = { };
                    };
                  };

                  generated = import "${inputs.kubenix}/jobs/generators/k8s" {
                    name = "kubenix-generated-for-crds";
                    inherit pkgs lib;
                    spec = "${allCrdsOpenApiDefinition}";
                  };

                  definitions =
                    (import "${generated}" {
                      inherit config lib;
                      options = null;
                    }).config.definitions;

                  customTypes = (
                    builtins.map (crdVersion: {
                      inherit (crdVersion)
                        group
                        version
                        kind
                        attrName
                        ;
                      module = lib.types.submodule (definitions."${crdVersion.fqdn}");
                    }) schemasFlattened
                  );
                in
                {
                  imports = [ kubenix.modules.k8s ];
                  kubernetes.customTypes = customTypes;

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
                        version = "2.6.4";
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
                      prune = true;
                      sourceRef = {
                        kind = "OCIRepository";
                        name = "flux-system";
                      };
                    };
                  };

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
                      dependsOn = [ { name = "infra"; } ];
                      interval = "1m0s";
                      path = "./";
                      prune = true;
                      sourceRef = {
                        kind = "OCIRepository";
                        name = "apps";
                      };
                    };
                  };

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

                  kubernetes.resources.tasks.goodbye = {
                    metadata.namespace = "default";
                    spec = {
                      params = [
                        {
                          name = "username";
                          type = "string";
                        }
                      ];
                      steps = [
                        {
                          name = "goodbye";
                          image = "alpine";
                          script = ''
                            #!/bin/sh
                            echo "Goodbye $(params.username)!"
                          '';
                        }
                      ];
                    };
                  };

                  kubernetes.resources.pipelines.hello-goodbye = {
                    metadata.namespace = "default";
                    spec = {
                      tasks = [
                        {
                          name = "goodbye";
                          taskRef.name = "goodbye";
                          params = [
                            {
                              name = "username";
                              value = "a";
                            }
                          ];
                        }
                      ];
                    };
                  };
                };
            }).config.kubernetes.resultYAML;
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt-rfc-style
              just
              nushell
              yq-go
              kubectl
              kind
              tilt
              fluxcd
              tektoncd-cli
            ];
          };
        };
    };
}
