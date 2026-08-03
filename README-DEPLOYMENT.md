# GST Billing: Kubernetes and Jenkins deployment

This project packages the supplied Django application for Linux and Kubernetes.
It also restores the missing `gstbilling` Django project package: upstream records it as a Git submodule without a URL, which prevents a normal clone from running.

## Prerequisites

- A Linux Kubernetes cluster with `kubectl` access and a default `StorageClass`.
- An NGINX Ingress Controller. Configure TLS through cert-manager or create `gst-billing-tls` yourself.
- A container registry Jenkins can push to.
- Jenkins agent with Docker CLI/daemon and `kubectl` installed.

## First deployment

Change `gst-billing.example.com` in `k8s/configmap.yaml` and `k8s/ingress.yaml` to your DNS name. Then create the namespace and application secret. Do not apply `secret.example.yaml` unchanged.

```sh
kubectl apply -f k8s/namespace.yaml
kubectl -n gst-billing create secret generic gst-billing-secrets \
  --from-literal=DJANGO_SECRET_KEY="$(openssl rand -base64 48)" \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 32)"
```

Create the registry pull secret if your registry is private, then add it under `spec.template.spec.imagePullSecrets` in `k8s/app.yaml`.

For a manual deployment, replace every instance of `registry.example.com/gst-billing:latest` in both `k8s/app.yaml` and `k8s/migration-job.yaml` with a real image tag and apply:

```sh
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/postgres.yaml
kubectl -n gst-billing wait --for=condition=ready pod -l app=postgres --timeout=180s
kubectl -n gst-billing delete job gst-billing-migrate --ignore-not-found
kubectl apply -f k8s/migration-job.yaml
kubectl -n gst-billing wait --for=condition=complete job/gst-billing-migrate --timeout=300s
kubectl apply -f k8s/app.yaml
kubectl apply -f k8s/ingress.yaml
kubectl -n gst-billing rollout status deployment/gst-billing
```

The bundled PostgreSQL StatefulSet is appropriate for a small self-managed installation. For production, use a managed PostgreSQL service or an operator-managed database, preserve backups, and set `POSTGRES_HOST` to that service.

## Jenkins setup

Create a Pipeline job from this repository. Jenkins needs these credentials:

- `container-registry`: username/password credential allowed to push to the registry.
- `kubeconfig-gst-billing`: secret-file credential containing the cluster kubeconfig. You may specify another credential ID through the build parameter.

Run the job with `REGISTRY` (for example, `registry.company.in`) and `IMAGE_REPOSITORY`. The pipeline runs a Django configuration check, builds and pushes a commit-tagged image, applies the manifests, waits for PostgreSQL, runs migrations once as a Kubernetes Job, and rolls out the image with zero unavailable replicas.

## Local image validation

```sh
docker build -t gst-billing:local .
docker run --rm -e DJANGO_SECRET_KEY=local-only -e POSTGRES_PASSWORD=local-only \
  -e DJANGO_ALLOWED_HOSTS=localhost gst-billing:local python manage.py check
```
