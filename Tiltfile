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
local_resource("flux-operator-setup", """
	kubectl wait -n flux-system --for condition=established --timeout=60s crd/fluxinstances.fluxcd.controlplane.io
	rm -f /tmp/kind-nix-testing-flux-operator-setup.yaml
	touch /tmp/kind-nix-testing-infra-dev.yaml
	touch /tmp/kind-nix-testing-apps-dev.yaml
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-infra:latest --insecure-registry --path /tmp/kind-nix-testing-infra-dev.yaml --source=local --revision=latest
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-apps:latest --insecure-registry --path /tmp/kind-nix-testing-apps-dev.yaml --source=local --revision=latest
	nix build --log-format raw --out-link /tmp/kind-nix-testing-flux-operator-setup.yaml .#flux-operator-setup
	kubectl apply -f /tmp/kind-nix-testing-flux-operator-setup.yaml
""")
local_resource("flux-infra", """
	kubectl wait -n flux-system fluxinstances/flux --for=condition=ready --timeout=10m
	rm -f /tmp/kind-nix-testing-infra.yaml
	nix build --log-format raw .#flux-resources --out-link /tmp/kind-nix-testing-infra-link.yaml
	cp /tmp/kind-nix-testing-infra-link.yaml /tmp/kind-nix-testing-infra.yaml
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-infra:latest --insecure-registry --path /tmp/kind-nix-testing-infra.yaml --source=local --revision=latest
	flux reconcile source oci flux-system
	flux reconcile kustomization infra
""")
local_resource("flux-apps", """
	kubectl wait -n flux-system kustomizations/infra --for=condition=ready --timeout=10m
	rm -f /tmp/kind-nix-testing-apps.yaml
	nix build --log-format raw .#kubernetes-sorted --out-link /tmp/kind-nix-testing-apps-link.yaml
	cp /tmp/kind-nix-testing-apps-link.yaml /tmp/kind-nix-testing-apps.yaml
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-apps:latest --insecure-registry --path /tmp/kind-nix-testing-apps.yaml --source=local --revision=latest
	flux reconcile source oci apps
	flux reconcile kustomization apps
""", deps=["flake.nix"])
