{
  lib,
  inputs,
  self,
  ...
}:
{
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
        ${pkgs.yq-go}/bin/yq eval-all '[.] | filter(.kind == "FluxInstance") | .[] | splitDoc' ${self'.packages.kubernetes-sorted} > $out
      '';
      packages.flux-resources = pkgs.runCommand "flux-resources" { } ''
        ${pkgs.yq-go}/bin/yq eval-all '[.] | filter(.metadata.namespace == "flux-system" or .kind == "Namespace") | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${self'.packages.kubernetes-sorted} > $out
      '';
      packages.kubernetes-sorted = pkgs.runCommand "flux-resources" { } ''
        ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${self'.packages.kubernetes} > $out
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
                        (pkgs.fetchurl {
                          url = "https://github.com/grafana/alloy-operator/releases/download/alloy-operator-0.3.9/collectors.grafana.com_alloy.yaml";
                          hash = "sha256-sj7vPTr4Naix3eESQGHHNKnsi5Ij+1wWKtNG3zkDhJM=";
                        })
                        (pkgs.fetchurl {
                          url = "https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml";
                          hash = "sha256-I+vgoWKA34lENBlbMZF3GBG7XAJTtsmbalwbxC5Tkvo=";
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

              generated = import "${inputs.kubenix}/pkgs/generators/k8s" {
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
              imports = [
                kubenix.modules.k8s
                self.modules.kubenix.default
              ];
              kubernetes.customTypes = customTypes;
            };
          specialArgs = {
            inputs = inputs';
          };
        }).config.kubernetes.resultYAML;
    };
}
