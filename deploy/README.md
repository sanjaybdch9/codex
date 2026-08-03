# Automated EKS deploy

Scripts that automate the [EKS beginner runbook](../README-DEPLOYMENT.md) for a **test deploy**
(no custom domain, in-cluster Postgres). Run them from the `deploy/` folder.

## What you must do by hand first (can't be scripted)

These need a browser or your own secret keys, so no script can do them for you:

1. **Create an AWS account** — <https://aws.amazon.com> (Runbook Part 1).
2. **Create an access key** — IAM → Users → `gst-admin` with *AdministratorAccess* → create access key (Runbook Part 2).
3. **Log the CLI in** — after installing tools, run `aws configure` and paste your Access Key ID + Secret.

## The scripts (run in order)

```bash
cd deploy

./install-tools.sh     # Installs Homebrew, AWS CLI, eksctl, kubectl, Docker Desktop
#   → then open Docker Desktop once, and run `aws configure`

./deploy.sh            # Builds the cluster, pushes the app, deploys it, prints your URL
./create-admin.sh      # Creates your admin login (asks for username/password)

# ...test the app at the URL deploy.sh printed...

./teardown.sh          # Deletes everything so charges stop
```

## Notes

- **`deploy.sh` is safe to re-run.** It skips the cluster and image repo if they already exist,
  and never overwrites your database password once created. Re-running redeploys the app.
- **Settings live in `config.env`** — region, cluster size, and the app's test-mode config.
  Edit before running if you want a different region or node size.
- 💵 **It costs ~$0.15–0.30/hour while running.** `./teardown.sh` stops that. The teardown script
  also reminds you to check for leftover load balancers/volumes in the AWS console.
- The build targets `linux/amd64` automatically — required because your Mac's chip differs from
  AWS's servers.
