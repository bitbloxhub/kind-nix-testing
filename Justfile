dev:
	#!/usr/bin/env nu
	podman build -f ./Containerfile.nix-snapshotter -t kind-nix-snapshotter
	try {
		kind get clusters | grep kind-nix-testing
	} catch {
		kind create cluster --config=kind.yaml
	}
	if (podman inspect -f '{{{{.State.Running}}' kind-nix-testing-registry | complete).stdout != "true\n" {
		podman run -d --restart=always -p "127.0.0.1:24921:5000" --network bridge --name "kind-nix-testing-registry" ghcr.io/project-zot/zot-linux-amd64
	}
	if (podman inspect -f="{{{{json .NetworkSettings.Networks.kind}}" "kind-nix-testing-registry" | complete).stdout == "null\n" {
		podman network connect "kind" "kind-nix-testing-registry"
	}
	rm -f /tmp/kind-nix-testing-flux-operator-setup.yaml
	touch /tmp/kind-nix-testing-flux-operator-setup.yaml
	rm -f /tmp/kind-nix-testing-flux-kustomization.yaml
	touch /tmp/kind-nix-testing-flux-kustomization.yaml
	tilt up --stream=true
