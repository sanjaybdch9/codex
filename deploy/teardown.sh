#!/usr/bin/env bash
# Deletes everything and stops the charges (Runbook Part 12).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
need eksctl; need kubectl

warn "This DELETES the '$CLUSTER_NAME' cluster and its load balancer. This cannot be undone."
read -r -p "Type 'delete' to confirm: " CONFIRM
[[ "$CONFIRM" == "delete" ]] || die "Aborted — nothing was deleted."

# Delete the load balancer first so AWS cleans it up (avoids an orphaned, billing ELB).
log "Removing the load balancer service…"
kubectl -n "$K8S_NAMESPACE" delete service gst-billing --ignore-not-found >/dev/null 2>&1 || true
sleep 8

log "Deleting the EKS cluster — this takes ~10 minutes…"
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"

read -r -p "Also delete the ECR image repository '$ECR_REPO'? [y/N] " DEL_ECR
if [[ "$DEL_ECR" =~ ^[Yy]$ ]]; then
  aws ecr delete-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" --force >/dev/null 2>&1 \
    && ok "ECR repository deleted." || warn "Could not delete ECR repository (may not exist)."
fi

echo
ok "Teardown complete."
warn "Final safety check: in the AWS console (region $AWS_REGION), open"
echo "  • EC2 → Load Balancers   and   • EC2 → Volumes"
echo "and delete anything named 'gst-billing' that's still listed. Then you're back to \$0."
