dev:
	#!/usr/bin/env nu
	podman build -f ./Containerfile.nix-snapshotter -t kind-nix-snapshotter
	tilt up --stream=true
