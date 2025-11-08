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
      inputs',
      self',
      pkgs,
      system,
      ...
    }:
    {
      packages.kustomization-sources =
        pkgs.stdenv.mkDerivation {
          name = "kustomization-sources";
          dontUnpack = true;
          installPhase = ''
            ${builtins.concatStringsSep "\n" (
              builtins.map (name: ''
                mkdir -p $out/${name}
                ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${
                  self'.packages.kustomization-sources.${name}.config.kubernetes.resultYAML
                } > $out/${name}/${name}.yaml
              '') (builtins.filter (name: name != "default") (builtins.attrNames self.modules.kubenix))
            )}
          '';
        }
        // (builtins.listToAttrs (
          builtins.map (name: {
            name = name;
            value = (
              inputs.kubenix.evalModules.${system} {
                module =
                  {
                    kubenix,
                    ...
                  }:
                  let
                    # A bunch of annoying stuff to get CRDs to work
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
                      builtins.concatMap processCrd (lib.importJSON self'.packages.crds);

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
                      self.modules.kubenix.${name}
                    ];
                    kubernetes.customTypes = customTypes;
                  };
                specialArgs = {
                  inherit
                    inputs'
                    self
                    self'
                    system
                    ;
                };
              }
            );
          }) (builtins.filter (name: name != "default") (builtins.attrNames self.modules.kubenix))
        ));
      packages.kubernetes-sorted = pkgs.runCommand "flux-resources" { } ''
        ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${self'.packages.kubernetes} > $out
      '';
    };
}
