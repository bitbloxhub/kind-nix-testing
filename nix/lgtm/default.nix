{
  lib,
  inputs,
  ...
}:
{
  flake.modules.kubenix.default =
    { pkgs, inputs, ... }:
    {
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
        spec = {
          interval = "1h0s";
          type = "oci";
          url = "oci://ghcr.io/grafana/helm-charts/";
        };
      };

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
                structuredConfig = {
                  # FIXME: this is being randomly set to true sometimes
                  auth_enabled = false;
                  bloom_build.enabled = false;
                  bloom_gateway.enabled = false;
                  chunk_store_config = {
                    chunk_cache_config = {
                      background = {
                        writeback_buffer = 500000;
                        writeback_goroutines = 1;
                        writeback_size_limit = "500MB";
                      };
                      default_validity = "0s";
                      memcached = {
                        batch_size = 4;
                        parallelism = 5;
                      };
                      memcached_client = {
                        addresses = "dnssrvnoa+_memcached-client._tcp.loki-loki-chunks-cache.loki.svc";
                        consistent_hash = true;
                        max_idle_conns = 72;
                        timeout = "2000ms";
                      };
                    };
                  };
                  common = {
                    compactor_grpc_address = "loki-backend.loki.svc:9095";
                    path_prefix = "/var/loki";
                    replication_factor = 3;
                    storage.s3 = {
                      access_key_id = "root-user";
                      bucketnames = "chunks";
                      endpoint = "loki-loki-minio.loki.svc:9000";
                      insecure = true;
                      s3forcepathstyle = true;
                      secret_access_key = "supersecretpassword";
                    };
                  };
                  frontend = {
                    scheduler_address = "";
                    tail_proxy_url = "";
                  };
                  frontend_worker.scheduler_address = "";
                  index_gateway.mode = "simple";
                  ingester.chunk_encoding = "snappy";
                  limits_config = {
                    allow_structured_metadata = true;
                    max_cache_freshness_per_query = "10m";
                    query_timeout = "300s";
                    reject_old_samples = true;
                    reject_old_samples_max_age = "168h";
                    split_queries_by_interval = "15m";
                    volume_enabled = true;
                  };
                  memberlist.join_members = ["loki-memberlist"];
                  pattern_ingester.enabled = true;
                  querier.max_concurrent = 4;
                  query_range = {
                    align_queries_with_step = true;
                    cache_results = true;
                    results_cache.cache = {
                      background = {
                        writeback_buffer = 500000;
                        writeback_goroutines = 1;
                        writeback_size_limit = "500MB";
                      };
                      default_validity = "12h";
                      memcached_client = {
                        addresses = "dnssrvnoa+_memcached-client._tcp.loki-loki-chunks-cache.loki.svc";
                        consistent_hash = true;
                        timeout = "500ms";
                        update_interval = "1m";
                      };
                    };
                  };
                  ruler = {
                    storage.s3.bucketnames = "ruler";
                    storage.type = "s3";
                    wal.dir = "/var/loki/ruler-wal";
                  };
                  runtime_config.file = "/etc/loki/runtime-config/runtime-config.yaml";
                  schema_config.configs = [
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
                  server = {
                    grpc_listen_port = 9095;
                    http_listen_port = 3100;
                    http_server_read_timeout = "600s";
                    http_server_write_timeout = "600s";
                  };
                  storage_config = {
                    bloom_shipper.working_directory = "/var/loki/data/bloomshipper";
                    boltdb_shipper.index_gateway_client.server_address = "dns+loki-backend-headless.loki.svc:9095";
                    hedging = {
                      at = "250ms";
                      max_per_second = 20;
                      up_to = 3;
                    };
                    tsdb_shipper.index_gateway_client.server_address = "dns+loki-backend-headless.loki.svc:9095";
                    use_thanos_objstore = false;
                  };
                  tracing.enabled = false;
                };
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

      kubernetes.resources.helmreleases.grafana-operator = {
        metadata.namespace = "flux-system";
        spec = {
          interval = "1m0s";
          timeout = "1m0s";
          chart.spec = {
            chart = "grafana-operator";
            version = "v5.19.4";
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

      kubernetes.resources.alloys.alloy = {
        metadata.namespace = "alloy";
        spec.alloy = {
          mounts.varlog = true;
          configMap.content = ''
            logging {
              level  = "info"
              format = "logfmt"
            }

            discovery.kubernetes "pods" {
              role = "pod"
            }

            discovery.relabel "pods" {
              targets = discovery.kubernetes.pods.targets

              rule {
                action        = "replace"
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
              }
              rule {
                action        = "replace"
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod_name"
              }
              rule {
                action        = "replace"
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "container_name"
              }
            }

            prometheus.remote_write "mimir" {
              endpoint {
                url = "http://mimir-mimir-distributed-nginx.mimir.svc:80/api/v1/push"
              }
            }

            prometheus.scrape "pods" {
              targets = discovery.relabel.pods.output
              forward_to = [prometheus.remote_write.mimir.receiver]
            }

            loki.source.kubernetes "pods" {
              targets    = discovery.kubernetes.pods.targets
              forward_to = [loki.write.endpoint.receiver]
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
