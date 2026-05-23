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
            inherit name;
            value = inputs.kubenix.evalModules.${system} {
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
                        inherit (crd.spec) group;
                        version = version.name;
                        inherit (crd.spec.names) kind;
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

                  inherit
                    ((import "${generated}" {
                      inherit config lib;
                      options = null;
                    }).config
                    )
                    definitions
                    ;

                  schemaType = schema:
                    if (schema."x-kubernetes-int-or-string" or false) == true then lib.types.either lib.types.int lib.types.str
                    else if schema ? oneOf || schema ? anyOf || schema ? allOf then lib.types.anything
                    else if schema ? type then
                      if schema.type == "string" then lib.types.str
                      else if schema.type == "integer" || schema.type == "number" then lib.types.int
                      else if schema.type == "boolean" then lib.types.bool
                      else if schema.type == "array" then lib.types.listOf (schemaType (schema.items or { type = "object"; }))
                      else if schema.type == "object" then
                        if schema ? properties then
                          lib.types.submodule ({ ... }:
                            {
                              options = schemaOptions schema;
                            }
                            // lib.optionalAttrs ((schema.additionalProperties or false) == true) {
                              freeformType = lib.types.attrs;
                            })
                        else if schema ? additionalProperties && builtins.isAttrs schema.additionalProperties then
                          lib.types.attrsOf (schemaType schema.additionalProperties)
                        else lib.types.attrs
                      else lib.types.anything
                    else if schema ? properties then
                      lib.types.submodule ({ ... }: {
                        options = schemaOptions schema;
                      })
                    else lib.types.anything;

                  schemaOptions = schema:
                    let
                      properties = schema.properties or { };
                      required = schema.required or [ ];
                    in
                    builtins.mapAttrs (propName: propSchema:
                      lib.mkOption {
                        type =
                          if builtins.elem propName required
                          then schemaType propSchema
                          else lib.types.nullOr (schemaType propSchema);
                        default = null;
                      }
                    ) properties;

                  customTypes = builtins.map (crdVersion: {
                    inherit (crdVersion)
                      group
                      version
                      kind
                      attrName
                      ;
                    module = {
                      options = schemaOptions (crdVersion.schema.properties.spec or { type = "object"; });
                      freeformType = lib.types.attrs;
                    };
                  }) schemasFlattened;
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
            };
          }) (builtins.filter (name: name != "default") (builtins.attrNames self.modules.kubenix))
        ));
      packages.kubernetes-sorted = pkgs.runCommand "flux-resources" { } ''
        ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${self'.packages.kubernetes} > $out
      '';
    };
}
