# Kong POC — option A (Kong Manager, self-hosted)

Option A of the Kong Enterprise POC, built for comparison with option C
([kong-poc](https://github.com/Efrat-Gortler/kong-poc): DB-less Kong managed by KIC from Git, blocking service).

Here **everything that changes day to day — services, routes, rate limits, blocks — is managed in Kong Manager**
(stored in Postgres). There is no blocking service, no OPA and no route configuration in Git. This repository only
installs the infrastructure, with plain Helm (no Argo CD):

| Path | What |
|---|---|
| `docs/OPTION-A-DESIGN.md` | design, findings, free mode vs licensed, build plan |
| `scripts/bootstrap.sh` | once: namespaces `konga-*`, Secrets (Postgres password, hybrid cluster certificate) |
| `scripts/deploy.sh <cp\|leg1\|leg2>` | `helm upgrade --install` of the control plane (+ Postgres) or a data plane |
| `scripts/demo-config.sh [delete]` | example configuration through the Admin API (tag `option-a-demo`) - Kong Manager is read-only in free mode |
| `charts/postgres` | Postgres for the control plane |
| `values/` | values for the official `kong/kong` chart (pinned in `scripts/lib.sh`) |
| `windows/hosts-konga.cmd` | adds the Kong Manager / Admin API host names to the Windows hosts file (asks for the VM IP) |

Shared with option C and used as they are (in `kong-poc`): Redis (`gw-shared`), Keycloak (`idp`), the acceptance
tests, the `redis` / `mock-service` / `gslb-sim` charts.

**No Enterprise license yet:** runs in free mode (Kong Gateway Enterprise 3.14 without a license). Kong Manager and
the Admin API have **no login** in free mode — they are exposed only on the POC routes. See the design document for
what is added once a license exists.

```bash
scripts/bootstrap.sh          # asks before creating namespaces
scripts/deploy.sh cp
```

No secrets, passwords or licenses in this repository: they live only in OpenShift Secrets.
