#!/usr/bin/env bash
# Clean up completed and failed pods across all namespaces

set -euo pipefail

kubectl get pods -A -o json | \
  jq -r '.items[] | select(
    .status.phase == "Succeeded" or
    .status.phase == "Failed" or
    .status.reason == "Evicted" or
    .status.reason == "ContainerStatusUnknown" or
    (.status.containerStatuses[]?.state.waiting.reason == "ContainerStatusUnknown")
  ) | "\(.metadata.namespace) \(.metadata.name) \(.status.reason // .status.phase)"' | \
  while read -r ns name reason; do
    echo "Deleting $reason pod: $ns/$name"
    kubectl delete pod -n "$ns" "$name"
  done
