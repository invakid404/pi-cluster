#!/usr/bin/env bash

kubectl create namespace flux-system

export SOPS_PGP_FP=$(cat .sops.yaml | yq -r '.creation_rules[0].pgp')

gpg --export-secret-keys --armor "${SOPS_PGP_FP}" |
	kubectl create secret generic sops-gpg \
	--namespace=flux-system \
	--from-file=sops.asc=/dev/stdin

# The image-reflector + image-automation controllers are enabled in the committed
# clusters/styx/flux-system/gotk-components.yaml (Flux v2.8.x, commit 0d1efc6). Keep
# --components-extra in sync so a re-bootstrap regenerates the components WITH image
# automation instead of silently dropping it and breaking self-updating deploys.
flux bootstrap github \
  --owner=invakid404 \
  --repository=pi-cluster \
  --path=clusters/styx \
  --personal \
  --token-auth \
  --components-extra=image-reflector-controller,image-automation-controller
