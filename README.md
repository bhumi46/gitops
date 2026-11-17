# gitops

Desired state for the IDP lab. Argo CD's `root` app (created by `platform-infra`) watches `apps/` recursively and applies everything in it.

## Layout

```
apps/
  repositories/ghcr-charts.yaml   Argo CD repo: public Helm OCI registry ghcr.io/bhumi46/charts
  <svc>-<env>.yaml                Application per service per env
envs/
  <env>/<svc>/values.yaml         per-env Helm values (image.tag, replicas, env vars)
scripts/promote.sh                open a PR copying a dev tag to another env
```

Each Application has **two sources**: the chart from `oci://ghcr.io/bhumi46/charts/<svc>` and `$values/envs/<env>/<svc>/values.yaml` from this repo (`ref: values`). Destination namespace = env (created by Terraform), `syncPolicy.automated` with prune + selfHeal, label `app.kubernetes.io/name=<svc>` (used by the Backstage Argo CD plugin).

## Flow

- **dev:** each merge to `main` in a service repo makes CI commit `image.tag: <sha>` to `envs/dev/<svc>/values.yaml`. Argo CD rolls it out.
- **staging:** promoted by PR: `scripts/promote.sh <svc> [staging]`, review, merge.
- **rollback:** `git revert <commit>` here and push. Argo CD syncs back to the previous tag.

## Adding a service or environment

Add `apps/<svc>-<env>.yaml` and `envs/<env>/<svc>/values.yaml` (the Backstage templates open PRs that do exactly this). The namespace must exist first (`platform-infra/envs/local/environments/<env>.yaml`).

## Pinned versions

| What | Version |
|---|---|
| Chart `users-svc` | 0.1.0 |
| Chart `orders-svc` | 0.1.0 |
| yq (CI bump, promote script) | v4.54.3 |
