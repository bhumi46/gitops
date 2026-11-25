# gitops

Desired state for the IDP lab. Argo CD's `root` app (created by `platform-infra`) watches `apps/` recursively and applies everything in it.

## Layout

```
apps/
  repositories/ghcr-charts.yaml   Argo CD repo: public Helm OCI registry ghcr.io/bhumi46/charts
  <svc>-<env>.yaml                Application per service per env
  backstage.yaml                  the developer portal itself (namespace backstage, step 4e)
envs/
  <env>/<svc>/values.yaml         per-env Helm values (replicas, env vars, feature flags)
  <env>/<svc>/image.yaml          which build runs (image.tag only); the only file a deploy changes
  <env>/<svc>/deploy.yaml         deploy mode: auto (CI deploys every main commit) | approval (PR)
platform/
  backstage/{values,image,deploy}.yaml   the portal itself (same split as envs/)
scripts/promote.sh                open a deploy PR (promote from an env, or a specific --tag)
```

Each Application has **two sources**: the chart from `oci://ghcr.io/bhumi46/charts/<svc>` and `$values/envs/<env>/<svc>/values.yaml` + `image.yaml` from this repo (`ref: values`). Destination namespace = env (created by Terraform), `syncPolicy.automated` with prune + selfHeal, label `app.kubernetes.io/name=<svc>` (used by the Backstage Argo CD plugin).

## Flow

- **dev:** each merge to `main` in a service repo makes CI commit `image.tag: <sha>` to `envs/dev/<svc>/values.yaml`. Argo CD rolls it out.
- **staging:** promoted by PR: `scripts/promote.sh <svc> [staging]`, review, merge.
- **rollback:** `git revert <commit>` here and push. Argo CD syncs back to the previous tag.

## How deploys work

Services follow a release lifecycle (details: [platform-workflows](https://github.com/bhumi46/platform-workflows)):

| Service branch | Builds | Goes to |
|---|---|---|
| `develop` | app `X.Y.Z-dev.N`, chart `A.B.C-dev.M` | dev |
| `release/X.Y`, `hotfix/X.Y.Z` | `X.Y.Z-rc.N` | qa |
| `main` (release merged = tested and verified) | final `X.Y.Z` (the tested rc image, re-tagged) | staging (prod later) |

What an environment runs is two values here: the **app version** in `envs/<env>/<svc>/image.yaml`
(`image.tag`) and the **chart version** in `apps/<svc>-<env>.yaml` (`targetRevision`). A deploy changes
exactly those two lines.

**Deploy mode** per service and environment, in `envs/<env>/<svc>/deploy.yaml`:

| `mode` | What CI does after a build |
|---|---|
| `auto` | commits the new versions on `main`; Argo CD deploys them |
| `approval` | keeps **one rolling PR** `deploy/<env>/<svc>` pointing at the newest build. **Merging it deploys**; nothing deploys until then |

Defaults: `auto` for dev, `approval` for qa and staging. Changing a mode is itself a reviewed PR here.

**Choosing a version yourself** (promote qa → staging, an older build, a rollback): Backstage
**Deploy service**, or `scripts/promote.sh`. Either way it's a PR; merging it is the approval.

**Policy** (`pr-check.yml` on every PR): staging/prod only accept final releases `X.Y.Z` (no `-dev`/`-rc`,
no commit SHAs); versions never go backwards unless the PR has the `rollback` label; every changed
Application must render with helm. Shared CI never moves an environment backwards either.

## Adding a service or environment

Add `apps/<svc>-<env>.yaml` and `envs/<env>/<svc>/values.yaml` (the Backstage templates open PRs that do exactly this). The namespace must exist first (`platform-infra/envs/local/environments/<env>.yaml`).

## Pinned versions

| What | Version |
|---|---|
| Chart `users-svc` | 0.1.0 |
| Chart `orders-svc` | 0.1.0 |
| yq (CI bump, promote script) | v4.54.3 |
