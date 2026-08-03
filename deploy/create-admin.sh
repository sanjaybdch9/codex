#!/usr/bin/env bash
# Creates your admin login on the running app (Runbook Part 10).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
need kubectl

kubectl -n "$K8S_NAMESPACE" get deployment gst-billing >/dev/null 2>&1 \
  || die "The app isn't deployed yet. Run  ./deploy.sh  first."

read -r -p "Admin username: " SU_USER
read -r -p "Admin email:    " SU_EMAIL
read -r -s -p "Admin password: " SU_PASS; echo
[[ -n "$SU_USER" && -n "$SU_PASS" ]] || die "Username and password are both required."

log "Creating admin user '$SU_USER'…"
if kubectl -n "$K8S_NAMESPACE" exec -i deploy/gst-billing -- \
     env DJANGO_SUPERUSER_USERNAME="$SU_USER" \
         DJANGO_SUPERUSER_EMAIL="$SU_EMAIL" \
         DJANGO_SUPERUSER_PASSWORD="$SU_PASS" \
     python manage.py createsuperuser --noinput; then
  ok "Admin user '$SU_USER' created. Sign in at the /admin/ URL."
else
  warn "Could not create the user — it may already exist. Try a different username, or reset via the app."
fi
