{
  lib,
  inputs,
  ...
}:
{
  flake.modules.kubenix.lgtm-operators = {
    kubernetes.resources.namespaces.mimir = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "mimir";
    };

    kubernetes.resources.namespaces.loki = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "loki";
    };

    kubernetes.resources.namespaces.alloy = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "alloy";
    };

    kubernetes.resources.namespaces.grafana = {
      metadata.annotations.apply-order = "100";
      metadata.labels.name = "grafana";
    };

    kubernetes.resources.helmrepositories.grafana = {
      metadata.namespace = "flux-system";
      metadata.annotations = {
        apply-order = "100";
      };
      spec = {
        interval = "1h0s";
        type = "oci";
        url = "oci://ghcr.io/grafana/helm-charts/";
      };
    };

    kubernetes.resources.helmreleases.grafana-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        timeout = "1m0s";
        chart.spec = {
          chart = "grafana-operator";
          version = "v5.20.0";
          sourceRef = {
            kind = "HelmRepository";
            name = "grafana";
          };
        };
        values = {
          namespaceOverride = "grafana";
        };
      };
    };

    kubernetes.resources.helmreleases.alloy-operator = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        timeout = "1m0s";
        chart.spec = {
          chart = "alloy-operator";
          version = "0.3.9";
          sourceRef = {
            kind = "HelmRepository";
            name = "grafana";
          };
        };
        values = {
          namespaceOverride = "alloy";
        };
      };
    };
  };

  flake.modules.kubenix.lgtm = {
    kustomization.dependsOn = [
      {
        name = "lgtm-operators";
      }
    ];

    kubernetes.resources.helmreleases.mimir-distributed = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        timeout = "5m0s";
        targetNamespace = "mimir";
        chart.spec = {
          chart = "mimir-distributed";
          version = "5.8.0";
          sourceRef = {
            kind = "HelmRepository";
            name = "grafana";
          };
        };
        values = {
          runtimeConfig.overrides.anonymous.max_global_series_per_user = 1500000;
        };
      };
    };

    kubernetes.resources.jobs.loki-minio-make-buckets = {
      metadata.namespace = "loki";
      spec = {
        template = {
          spec = {
            restartPolicy = "OnFailure";
            volumes = [
              {
                name = "minio-configuration";
                projected.sources = [
                  {
                    configMap.name = "loki-loki-minio";
                  }
                  {
                    secret.name = "loki-loki-minio";
                  }
                ];
              }
            ];
            serviceAccountName = "minio-sa";
            containers = [
              {
                name = "minio-mc";
                # TODO: generate this from the loki helm chart
                image = "quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "/bin/sh"
                  "/config/initialize"
                ];
                env = [
                  {
                    name = "MINIO_ENDPOINT";
                    value = "loki-loki-minio";
                  }
                  {
                    name = "MINIO_PORT";
                    value = "9000";
                  }
                ];
                volumeMounts = [
                  {
                    name = "minio-configuration";
                    mountPath = "/config";
                  }
                ];
                resources.requests.memory = "128Mi";
              }
            ];
          };
        };
      };
    };

    kubernetes.resources.helmreleases.loki = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "1m0s";
        timeout = "5m0s";
        targetNamespace = "loki";
        chart.spec = {
          chart = "loki";
          version = "6.37.0";
          sourceRef = {
            kind = "HelmRepository";
            name = "grafana";
          };
        };
        values =
          let
            ignoreAntiAffinity = {
              podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution = [
                {
                  labelSelector.matchLabels."app.kubernetes.io/component" = "ignore-anti-affinity";
                  topologyKey = "kubernetes.io/hostname";
                }
              ];
            };
          in
          {
            loki = {
              schemaConfig.configs = [
                {
                  from = "2024-04-01";
                  store = "tsdb";
                  object_store = "s3";
                  schema = "v13";
                  index = {
                    prefix = "loki_index_";
                    period = "24h";
                  };
                }
              ];
              ingester.chunk_encoding = "snappy";
              querier.max_concurrent = 4;
              pattern_ingester.enabled = true;
              limits_config = {
                allow_structured_metadata = true;
                volume_enabled = true;
              };
              auth_enabled = false;
            };
            deploymentMode = "SimpleScalable";
            backend.replicas = 2;
            backend.affinity = ignoreAntiAffinity;
            read.replicas = 2;
            read.affinity = ignoreAntiAffinity;
            write.replicas = 3;
            write.affinity = ignoreAntiAffinity;
            minio.enabled = true;
          };
      };
    };

    kubernetes.resources.alloys.alloy = {
      metadata.namespace = "alloy";
      spec.alloy = {
        mounts.varlog = true;
        configMap.content = ''
          logging {
            level = "info"
            format = "logfmt"
          }

          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_namespace"]
              target_label = "namespace"
            }

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label = "pod_name"
            }

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label = "container_name"
            }
          }

          prometheus.scrape "pods" {
            targets = discovery.relabel.pods.output
            forward_to = [prometheus.remote_write.mimir.receiver]
            scrape_interval = "10s"
          }

          discovery.relabel "pod_logs" {
            targets = discovery.kubernetes.pods.targets

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_namespace"]
              target_label = "namespace"
            }

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label = "pod"
            }

            rule {
              action = "replace"
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label = "container"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
              action = "replace"
              target_label = "app"
            }

            rule {
              source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
              action = "replace"
              target_label = "job"
              separator = "/"
              replacement = "$1"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
              action = "replace"
              target_label = "__path__"
              separator = "/"
              replacement = "/var/log/pods/*$1/*.log"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_container_id"]
              action = "replace"
              target_label = "container_runtime"
              regex = "^(\\S+):\\/\\/.+$"
              replacement = "$1"
            }
          }

          loki.source.kubernetes "pods" {
            targets = discovery.relabel.pod_logs.output
            forward_to = [loki.write.endpoint.receiver]
          }

          discovery.kubernetes "nodes" {
            role = "node"
          }

          prometheus.scrape "nodes_metrics" {
            targets = discovery.kubernetes.nodes.targets
            forward_to = [prometheus.remote_write.mimir.receiver]
            scheme = "https"
            bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            tls_config {
              ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
              insecure_skip_verify = true
            }
            scrape_interval = "10s"
          }

          discovery.relabel "nodes_cadvisor" {
            targets = discovery.kubernetes.nodes.targets
            rule {
              target_label = "__address__"
              replacement = "kubernetes.default.svc.cluster.local:443"
            }
            rule {
              source_labels = ["__meta_kubernetes_node_name"]
              regex = "(.+)"
              replacement = "/api/v1/nodes/''${1}/proxy/metrics/cadvisor"
              target_label = "__metrics_path__"
            }
          }

          prometheus.scrape "nodes_cadvisor" {
            targets = discovery.relabel.nodes_cadvisor.output
            forward_to = [prometheus.remote_write.mimir.receiver]
            scheme = "https"
            bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            tls_config {
              ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
              insecure_skip_verify = true
            }
            scrape_interval = "10s"
          }

          prometheus.remote_write "mimir" {
            endpoint {
              url = "http://mimir-mimir-distributed-nginx.mimir.svc:80/api/v1/push"
            }
          }

          loki.write "endpoint" {
            endpoint {
              url = "http://loki-loki-gateway.loki.svc:80/loki/api/v1/push"
              tenant_id = "local"
            }
          }
        '';
      };
    };

    kubernetes.resources.grafanas.grafana = {
      metadata.namespace = "grafana";
      metadata.labels.dashboards = "grafana";
      spec = {
        config.security = {
          admin_user = "root";
          admin_password = "secret";
        };
      };
    };

    kubernetes.resources.grafanadatasources.mimir = {
      metadata.namespace = "grafana";
      spec = {
        instanceSelector = {
          matchLabels.dashboards = "grafana";
        };
        datasource = {
          name = "Mimir";
          type = "prometheus";
          access = "proxy";
          url = "http://mimir-mimir-distributed-nginx.mimir.svc/prometheus";
          isDefault = true;
        };
      };
    };

    kubernetes.resources.grafanadatasources.loki = {
      metadata.namespace = "grafana";
      spec = {
        instanceSelector = {
          matchLabels.dashboards = "grafana";
        };
        datasource = {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://loki-loki-gateway.loki.svc/";
          isDefault = false;
        };
      };
    };
  };
}
