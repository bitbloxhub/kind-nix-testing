{
  lib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      ...
    }:
    let
      gerritOperator = pkgs.fetchFromGitHub {
        owner = "bitbloxhub";
        repo = "k8s-gerrit";
        rev = "9772a1389af5e3e9bb53f8a8a842f232f129f3f0";
        hash = "sha256-YVyHLn/urlnhCdxaSPMjIDYFF88ZSslbWsQssGs9UAo=";
      };
      gerritCrdsSrc = "${gerritOperator}/crd/current";
      gerritCrds = builtins.map (crd: "${gerritCrdsSrc}/${crd}") (
        builtins.attrNames (builtins.readDir gerritCrdsSrc)
      );
    in
    {
      packages.crds = pkgs.writeTextFile {
        name = "crds.json";
        text = builtins.toJSON (
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
                (
                  [
                    (pkgs.fetchurl {
                      url = "https://github.com/fluxcd/flux2/releases/download/v2.7.3/install.yaml";
                      hash = "sha256-7CZLGm/M4P+qUQXKSea9qDqloyqkhWAYdBGttybL9lY=";
                    })
                    (pkgs.fetchurl {
                      url = "https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.33.0/install.yaml";
                      hash = "sha256-QCDuEFDiRWGWapF2bcurX+KqGgGAwGLamM2vBMoa7x0=";
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
                      url = "https://github.com/grafana/grafana-operator/releases/v5.20.0/download/kustomize-cluster_scoped.yaml";
                      hash = "sha256-/cB1kzXNYfFTFosmgW8bdSlPBMhs46Kaj+Jk5mbaxT8=";
                    })
                  ]
                  ++ gerritCrds
                )
            )
          )
        );
      };
    };
}
