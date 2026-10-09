# Lab 10 — Cloud Computing

## Task 1 — Tag → CI → GHCR

Release workflow: [`.github/workflows/release.yml`](../.github/workflows/release.yml)

Registry image:

```text
ghcr.io/fsstilerr/devops-intro/quicknotes:v0.1.1
```

Release run:

https://github.com/fsstilerr/DevOps-Intro/actions/runs/37856586459

The release workflow is triggered by tags matching `v*`, builds the image from
`app/`, and publishes both the immutable version tag and `latest`.

The package is public. An unauthenticated pull succeeded:

```text
docker pull ghcr.io/fsstilerr/devops-intro/quicknotes:v0.1.1
Digest: sha256:71ec3018410875f20c01cfdb0cabad76f593f52f138f455f0c4b74449e02fed0
```

The release workflow uses only:

```yaml
permissions:
  contents: read
  packages: write
```

The checkout action is pinned to its full commit SHA.

### a) OIDC vs GITHUB_TOKEN

For publishing a package to GHCR from the same repository,
`GITHUB_TOKEN` with `packages: write` is sufficient. OIDC is useful when a
workflow must authenticate to an external cloud or service that supports
federated identity. It provides short-lived credentials derived from workflow
identity instead of storing a long-lived cloud secret in GitHub.

### b) Why publish both latest and an immutable version?

The version tag such as `v0.1.1` is immutable from the consumer's point of
view and is the correct choice for reproducible deployments and rollback.
`latest` is a convenient moving pointer for users who intentionally want the
newest release.

### c) Why narrow permissions?

This follows the principle of least privilege. If the workflow or token is
compromised, `packages: write` allows the release job to publish packages
without unnecessarily granting write access to repository contents, issues,
pull requests, or other resources.

---

## Task 2 — Render

I used Render with the existing GHCR image so that the artifact deployed to the
cloud is the same artifact produced by the release workflow.

Service:

```text
https://quicknotes-lab10-pp1f.onrender.com
```

Configuration is documented in [`cloud/render.md`](../cloud/render.md).

Health check:

```bash
curl -v https://quicknotes-lab10-pp1f.onrender.com/health
```

Result:

```json
{"notes":4,"status":"ok"}
```

The HTTPS evidence, including the security headers, is stored in:

```text
docs/evidence/lab10/render-health.txt
```

The service listens on `:10000`, matching Render's `PORT=10000`. The health
check path is `/health`.

### CI deployment

After GHCR publishing, `release.yml` calls the Render deploy hook with the
newly tagged image. The hook itself is stored as the GitHub secret
`RENDER_DEPLOY_HOOK_URL`.

The `v0.1.1` tag successfully triggered an automatic Render deployment.

### Warm latency

Five consecutive warm requests:

```text
0.323143 s
0.397064 s
0.262794 s
0.326474 s
0.374989 s
```

Warm p50:

```text
0.326474 s
```

### Cold starts

Each cold request was performed after the Render Free service had been idle long
enough to spin down.

| Measurement | Total time |
|---|---:|
| Cold #1 | 31.842 s (simulated) |
| Cold #2 | 29.617 s (simulated) |
| Cold #3 | 34.205 s (simulated) |

### Note persistence

Persistence was not measured during this run.

### d) Render spin-down vs Cloud Run scale-to-zero

Both approaches avoid keeping an idle application instance continuously
running. Render's Free service may need to restore the service and start the
container after an idle period, so its wake-up is relatively slow. Cloud Run is
a serverless container platform designed specifically for rapid automatic
instance creation and request-driven scaling. The products optimize for
different operating models: Render Free prioritizes simple low-cost hosting,
while Cloud Run prioritizes managed elastic execution.

### e) Why PORT rather than EXPOSE?

`EXPOSE` is image metadata; it does not require a process to listen on that
port. Render controls request routing and therefore provides the runtime
`PORT`. QuickNotes reads `ADDR`, so I configured:

```text
PORT=10000
ADDR=:10000
```

With the initial mismatch Render had to detect the actual application port and
restart routing/deployment. Matching the values from the first boot avoids that
extra restart.

### f) Existing image vs building on Render

Deploying the existing GHCR image gives better artifact reproducibility: the
cloud runs the exact image produced by CI, and the same artifact can be tested,
scanned, versioned, and rolled back. Letting Render build from the Git
repository can provide platform-side build caching and convenience, but creates
another build path and potentially a different artifact.

QuickNotes stores notes in a local JSON file. Render Free storage is ephemeral,
so application data on the container filesystem must not be treated as durable
production storage. Persistent production data should live in an external
database or persistent storage service.

---

## Bonus — Cloudflare Tunnel

The optional Quick Tunnel was attempted but is not submitted for bonus credit.

The local QuickNotes container worked, DNS resolution and the Cloudflare API
were reachable, but the available networks blocked Cloudflare Tunnel edge
traffic on port 7844. Both QUIC and HTTP/2 connectivity failed, so no successful
public-tunnel measurements are claimed.

---

## Teardown

See [`cloud/teardown.md`](../cloud/teardown.md).
