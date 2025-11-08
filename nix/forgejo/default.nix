{
  flake.modules.kubenix.forgejo =
    {
      pkgs,
      inputs',
      ...
    }:
    {
      kubernetes.resources.namespaces.forgejo = {
        metadata.annotations.apply-order = "100";
        metadata.labels.name = "forgejo";
      };

      kubernetes.resources.helmrepositories.forgejo-helm = {
        metadata.namespace = "flux-system";
        spec = {
          interval = "1h0s";
          type = "oci";
          url = "oci://code.forgejo.org/forgejo-helm/";
        };
      };

      kubernetes.resources.helmreleases.forgejo-helm = {
        metadata.namespace = "flux-system";
        spec = {
          interval = "1m0s";
          timeout = "1m0s";
          chart.spec = {
            chart = "forgejo";
            version = "14.0.0";
            sourceRef = {
              kind = "HelmRepository";
              name = "forgejo-helm";
            };
          };
          values =
            let
              forgejo = pkgs.forgejo.overrideAttrs (old: {
                doCheck = false;
                patches =
                  old.patches ++ (builtins.map (x: ./patches/${x}) (builtins.attrNames (builtins.readDir ./patches)));
              });
            in
            {
              namespaceOverride = "forgejo";
              gitea.config.queue.TYPE = "channel";
              gitea.config.server.ENABLE_PPROF = true;
              gitea.metrics.enabled = true;
              image.fullOverride = "nix:0${
                inputs'.nix-snapshotter.packages.nix-snapshotter.buildImage {
                  name = "forgejo";
                  resolvedByNix = true;
                  config.entrypoint = [
                    "${pkgs.bashInteractive}/bin/bash"
                    "-c"
                    "chown -R user:user /data/ && USER=root su user -c \"${forgejo}/bin/gitea web --config /data/gitea/conf/app.ini\""
                  ];
                  copyToRoot = [
                    (pkgs.buildEnv {
                      name = "system-path";
                      pathsToLink = [ "/bin" ];
                      paths = [
                        pkgs.bashInteractive
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.findutils
                        pkgs.gawk
                        pkgs.su
                        forgejo
                      ];
                    })
                    (pkgs.writeTextDir "/etc/pam.d/su" ''
                      # Allow root to bypass authentication (optional)
                      auth      sufficient pam_rootok.so

                      # For all users, always allow auth
                      auth      sufficient pam_permit.so

                      # Do not perform any account management checks
                      account   sufficient pam_permit.so

                      # No password management here (only needed if you are changing passwords)
                      # password  requisite pam_unix.so nullok yescrypt

                      # Keep session logging if desired
                      session   required pam_unix.so
                    '')
                    (pkgs.fakeNss.override {
                      extraPasswdLines = [ "user:x:1000:1000:new user:/tmp:/bin/sh" ];
                      extraGroupLines = [ "user:x:1000:" ];
                    })
                    pkgs.dockerTools.usrBinEnv
                  ];
                }
              }";
              image.rootless = false;
            };
        };
      };
    };
}
