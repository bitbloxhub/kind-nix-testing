allow_k8s_contexts("kind-kind-nix-testing")
local_resource("flux-operator", "kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.28.0/install.yaml")
local_resource("flux-operator-setup", """
	kubectl wait -n flux-system --for condition=established --timeout=60s crd/fluxinstances.fluxcd.controlplane.io
	rm -f /tmp/kind-nix-testing-flux-operator-setup.yaml
	nix build --out-link /tmp/kind-nix-testing-flux-operator-setup.yaml .#flux-operator-setup
	kubectl apply -f /tmp/kind-nix-testing-flux-operator-setup.yaml
""")
local_resource("flux-infra", """
	kubectl wait -n flux-system fluxinstances/flux --for=condition=ready --timeout=10m
	rm -f /tmp/kind-nix-testing-infra.yaml
	nix build .#flux-resources --out-link /tmp/kind-nix-testing-infra-link.yaml
	cp /tmp/kind-nix-testing-infra-link.yaml /tmp/kind-nix-testing-infra.yaml
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-infra:latest --insecure-registry --path /tmp/kind-nix-testing-infra.yaml --source=local --revision=latest
	flux reconcile source oci flux-system
	flux reconcile kustomization infra
""")
local_resource("flux-apps", """
	kubectl wait -n flux-system kustomizations/infra --for=condition=ready --timeout=10m
	rm -f /tmp/kind-nix-testing-apps.yaml
	nix build .#kubernetes-sorted --out-link /tmp/kind-nix-testing-apps-link.yaml
	cp /tmp/kind-nix-testing-apps-link.yaml /tmp/kind-nix-testing-apps.yaml
	flux push artifact oci://localhost:24921/kind-nix-testing-flux-apps:latest --insecure-registry --path /tmp/kind-nix-testing-apps.yaml --source=local --revision=latest
	flux reconcile source oci apps
	flux reconcile kustomization apps
""", deps=["flake.nix"])
