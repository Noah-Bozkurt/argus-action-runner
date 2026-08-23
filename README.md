# Argus Action Runner

A small Docker image for running GitHub Actions self-hosted runners used by Argus. It builds on GitHub's official `ghcr.io/actions/actions-runner` image and adds the native build packages and Docker Compose support required by Argus CI.

The image is published as:

```text
ghcr.io/noah-bozkurt/argus-action-runner:main
```

## Runner layout

The supplied Compose file runs three explicit runners on one Docker host instead of three identical scaled replicas:

- `argus-runner-rust` — labels `argus,docker,rust`; owns persistent Rust toolchain, Cargo home and target caches.
- `argus-runner-general-1` — labels `argus,docker,general`; shares a persistent pnpm store with the second general runner.
- `argus-runner-general-2` — labels `argus,docker,general`; shares the same persistent pnpm store.

This keeps Rust work on one warm runner and avoids repeatedly uploading and downloading large GitHub Actions caches. `CARGO_BUILD_JOBS` defaults to `3`, so Cargo does not try to consume every CPU on the host while general jobs are running.

## What is included

- GitHub Actions runner 2.336.0
- Docker CLI and Buildx from the official runner image
- Docker Compose 5.4.0
- Common Rust/native build dependencies (`build-essential`, `pkg-config`, OpenSSL headers)
- Git, curl, jq, Python 3, rsync, shellcheck and zstd
- Writable cache directories under `/home/runner/.cache/argus`

Rust, Node.js and pnpm versions remain controlled by the consuming workflow (`dtolnay/rust-toolchain`, `actions/setup-node`, and `pnpm/action-setup`) so repository CI remains explicit about tool versions. The expensive toolchain/package/build state is persisted locally by Compose instead of using remote GitHub cache archives.

## Run it

Create the local configuration:

```bash
cp .env.example .env
printf 'DOCKER_GID=%s\n' "$(stat -c '%g' /var/run/docker.sock)" >> .env
mkdir -p secrets
printf '%s' 'YOUR_FINE_GRAINED_PAT' > secrets/runner_pat
chmod 600 .env secrets/runner_pat
```

For an organization-scoped runner, use a fine-grained token with **Self-hosted runners: Read and write** organization permission. For a repository-scoped runner, use **Administration: Read and write** on that repository.

Start all three runners:

```bash
docker compose up -d
```

Do not use `--scale runner=3`; the services are intentionally separate so GitHub can route Rust and general workloads differently.

Use the Rust runner from a workflow with:

```yaml
runs-on: [self-hosted, linux, x64, argus, rust]
```

Use either general runner with:

```yaml
runs-on: [self-hosted, linux, x64, argus, general]
```

## Updating an existing scaled installation

After this change is published, replace the old scaled `runner` service with the explicit services:

```bash
docker compose down --remove-orphans
docker compose pull
docker compose up -d
```

Then confirm GitHub shows `argus-runner-rust`, `argus-runner-general-1`, and `argus-runner-general-2` online before changing consuming workflows to require the new `rust` or `general` labels.

The named cache volumes survive normal container recreation. Remove them only when you intentionally want a cold cache:

```bash
docker compose down -v
```

## Persistent caches

The Rust runner mounts:

```text
/home/runner/.rustup
/home/runner/.cache/argus/cargo-home
/home/runner/.cache/argus/cargo-target
```

The two general runners share:

```text
/home/runner/.cache/argus/pnpm
```

Keeping `CARGO_TARGET_DIR` outside the checked-out repository is important because `actions/checkout` can clean workspace-local `target/` directories on reused self-hosted runners.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `RUNNER_URL` | `https://github.com/Noah-Bozkurt` | Organization or repository URL to register against |
| `RUNNER_SCOPE` | `org` | `org` or `repo` |
| `RUNNER_NAME_PREFIX` | `argus-runner` | Prefix for the three fixed runner names |
| `RUNNER_RUST_LABELS` | `argus,docker,rust` | Labels assigned to the Rust runner |
| `RUNNER_GENERAL_LABELS` | `argus,docker,general` | Labels assigned to both general runners |
| `RUNNER_GROUP` | unset | Optional organization runner group |
| `CARGO_BUILD_JOBS` | `3` | Maximum parallel Cargo build jobs on the Rust runner |
| `DOCKER_GID` | required | Group ID owning the host Docker socket |

`RUNNER_CFG_PAT_FILE` is used by the supplied Compose file so the PAT is mounted as a file instead of being passed to workflow processes as an environment variable. The entrypoint also unsets registration credentials before starting the runner.

A one-time GitHub runner registration token can alternatively be supplied as `RUNNER_TOKEN`, but automatic registration and clean deregistration across container recreation require the fine-grained PAT.

## Docker access

The Compose setup mounts `/var/run/docker.sock` so Argus workflows can build images and start integration-test containers. This gives a workflow effectively root-level control over the Docker host. Only trusted workflows should be allowed to run on these runners.

## Public repository warning

Do **not** run untrusted fork pull-request code on a persistent self-hosted runner. A malicious workflow can compromise the runner and, because this setup exposes the Docker socket, potentially the entire host.

For public repositories, keep fork/PR validation on GitHub-hosted runners and reserve this runner for trusted branches, releases, deployments, or explicitly trusted PRs. If using an organization runner, restrict its runner group to only the repositories that need it.

## Image publishing

`.github/workflows/image.yml` intentionally runs on `ubuntu-latest` rather than on this self-hosted runner. Pull requests build the image without publishing it. Pushes to `main` and version tags publish to GHCR with SHA/main/tag labels.
