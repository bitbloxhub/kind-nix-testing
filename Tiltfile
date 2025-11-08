# vim: set ft=starlark: -*- mode: python; -*-

allow_k8s_contexts("kind-kind-nix-testing")
local_resource("kind-cluster", cmd="kind delete cluster -n kind-nix-testing && kind create cluster --config=kind.yaml")
local_resource(
	"kind-nix-testing-registry",
	serve_cmd=" ".join([
		"podman run",
		"--replace",
		"--restart=always",
		"-p \"127.0.0.1:24921:5000\"" ,
		"--network bridge",
		"--net kind",
		"--name \"kind-nix-testing-registry\"",
		"ghcr.io/project-zot/zot-linux-amd64",
	]),
)
local_resource("flux-operator", "kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.33.0/install.yaml")
local_resource("flux-setup", """
	kubectl wait -n flux-system --for condition=established --timeout=60s crd/fluxinstances.fluxcd.controlplane.io
	nix build --log-format raw --out-link /tmp/kind-nix-testing-kustomization-sources-link .#kustomization-sources
	mkdir -p /tmp/kind-nix-testing-kustomization-sources/
	cp --no-preserve mode,ownership -rf /tmp/kind-nix-testing-kustomization-sources-link/* /tmp/kind-nix-testing-kustomization-sources/
	flux push artifact oci://localhost:24921/kind-nix-testing-flux:latest --insecure-registry --path /tmp/kind-nix-testing-kustomization-sources --source=local --revision=latest
	kubectl apply -f /tmp/kind-nix-testing-kustomization-sources/flux-setup/flux-setup.yaml
""")
