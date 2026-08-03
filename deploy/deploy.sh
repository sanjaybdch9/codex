#!/usr/bin/env bash
# End-to-end deploy of the GST Billing app to AWS EKS.
# Automates Runbook Parts 5–9. Safe to re-run: it skips work already done.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

# ── Preflight ────────────────────────────────────────────────────────
log "Checking prerequisites…"
for t in aws eksctl kubectl docker; do need "$t"; done
docker info >/dev/null 2>&1 \
  || die "Docker isn't running. Open Docker Desktop, wait for the whale icon, then rerun."
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "AWS CLI isn't logged in. Run  aws configure  first (Runbook Part 4)."
ok "Tools present, Docker running, AWS logged in."

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
PLACEHOLDER="registry.example.com/gst-billing:latest"
log "Target image: ${IMAGE}"

# ── 1. EKS cluster (idempotent) ──────────────────────────────────────
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  ok "Cluster '$CLUSTER_NAME' already exists — skipping creation."
else
  log "Creating EKS cluster '$CLUSTER_NAME' — this takes ~20 minutes. Grab a coffee…"
  eksctl create cluster \
    --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --nodes "$NODE_COUNT" --node-type "$NODE_TYPE" --managed
fi
log "Pointing kubectl at the cluster…"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

# ── 2. ECR repository (idempotent) ───────────────────────────────────
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
  ok "ECR repository '$ECR_REPO' already exists."
else
  log "Creating ECR repository '$ECR_REPO'…"
  aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" >/dev/null
fi

# ── 3. Build image for AWS's chip (amd64) and push ───────────────────
log "Logging Docker in to ECR…"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
log "Building image for linux/amd64 and pushing (a few minutes)…"
docker buildx build --platform linux/amd64 -t "$IMAGE" --push "$PROJECT_ROOT"
ok "Image pushed."

# ── 4. Namespace ─────────────────────────────────────────────────────
log "Applying namespace…"
kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"

# ── 5. Secrets (create once; never overwrite existing passwords) ─────
if kubectl -n "$K8S_NAMESPACE" get secret gst-billing-secrets >/dev/null 2>&1; then
  ok "Secrets already exist — keeping current passwords."
else
  log "Generating app secrets (Django key + Postgres password)…"
  kubectl -n "$K8S_NAMESPACE" create secret generic gst-billing-secrets \
    --from-literal=DJANGO_SECRET_KEY="$(openssl rand -base64 48)" \
    --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"
fi

# ── 6. Config (test-mode settings from config.env) ───────────────────
log "Applying app settings…"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: gst-billing-config
  namespace: ${K8S_NAMESPACE}
data:
  DJANGO_DEBUG: "${DJANGO_DEBUG}"
  DJANGO_ALLOWED_HOSTS: "${DJANGO_ALLOWED_HOSTS}"
  DJANGO_TIME_ZONE: "${DJANGO_TIME_ZONE}"
  DJANGO_SECURE_COOKIES: "${DJANGO_SECURE_COOKIES}"
  POSTGRES_HOST: "postgres"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "gstbilling"
  POSTGRES_USER: "gstbilling"
EOF

# ── 7. PostgreSQL ────────────────────────────────────────────────────
log "Starting PostgreSQL…"
kubectl apply -f "$PROJECT_ROOT/k8s/postgres.yaml"
kubectl -n "$K8S_NAMESPACE" wait --for=condition=ready pod -l app=postgres --timeout=240s

# ── 8. Database migrations (run once as a Job) ───────────────────────
log "Running database migrations…"
kubectl -n "$K8S_NAMESPACE" delete job gst-billing-migrate --ignore-not-found >/dev/null 2>&1 || true
sed "s|${PLACEHOLDER}|${IMAGE}|g" "$PROJECT_ROOT/k8s/migration-job.yaml" | kubectl apply -f -
kubectl -n "$K8S_NAMESPACE" wait --for=condition=complete job/gst-billing-migrate --timeout=300s

# ── 9. Deploy the app ────────────────────────────────────────────────
log "Deploying the app…"
sed "s|${PLACEHOLDER}|${IMAGE}|g" "$PROJECT_ROOT/k8s/app.yaml" | kubectl apply -f -
# Force pods to pull the freshly-built image even when the tag is unchanged.
kubectl -n "$K8S_NAMESPACE" rollout restart deployment/gst-billing >/dev/null 2>&1 || true
kubectl -n "$K8S_NAMESPACE" rollout status deployment/gst-billing --timeout=300s

# ── 10. Expose with a public load balancer ───────────────────────────
log "Exposing the app with a load balancer…"
kubectl -n "$K8S_NAMESPACE" patch service gst-billing -p '{"spec":{"type":"LoadBalancer"}}' >/dev/null

log "Waiting for the public address (up to ~4 min)…"
HOSTNAME=""
for _ in $(seq 1 48); do
  HOSTNAME="$(kubectl -n "$K8S_NAMESPACE" get service gst-billing \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [[ -n "$HOSTNAME" ]] && break
  sleep 10
done

echo
if [[ -n "$HOSTNAME" ]]; then
  ok "Deployment complete!"
  printf '\n  %sApp URL:%s  http://%s/\n' "$BOLD" "$RST" "$HOSTNAME"
  printf '  %sAdmin:%s    http://%s/admin/\n\n' "$BOLD" "$RST" "$HOSTNAME"
  echo "The link may take another 2–3 minutes to respond while AWS warms up the load balancer."
  echo "Next:  ./create-admin.sh   to make your login."
  echo "Done testing?  ./teardown.sh   to delete everything and stop charges."
else
  warn "Load balancer address not ready yet. Check in a minute with:"
  echo "  kubectl -n $K8S_NAMESPACE get service gst-billing"
fi
