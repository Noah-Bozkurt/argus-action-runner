# Argus Action Runner

A small Docker image for running GitHub Actions self-hosted runners used by Argus. It builds on GitHub's official `ghcr.io/actions/actions-runner` image and adds the native build packages and Docker Compose support required by Argus CI.

The image is published as:

```text
ghcr.io/noah-bozkurt/argus-action-runner:main
```

## What is included

- GitHub Actions runner 2.336.0
- Docker CLI and Buildx from the official runner image
- Docker Compose 5.4.0
- Common Rust/native build dependencies (`build-essential`, `pkg-config`, OpenSSL headers)
- Git, curl, jq, Python 3, rsync, shellcheck and zstd

Rust, Node.js and pnpm versions remain controlled by the consuming workflow (`dtolnay/rust-toolchain`, `actions/setup-node`, and `pnpm/action-setup`) instead of being baked into this image.

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

Start one runner:

```bash
docker compose up -d
```

Start multiple runners for concurrent jobs:

```bash
docker compose up -d --scale runner=3
```

Each replica registers with a unique name based on its container hostname and receives the custom labels `argus` and `docker`. GitHub automatically adds the normal `self-hosted`, OS, and architecture labels.

Use it from a workflow with:

```yaml
runs-on: [self-hosted, linux, x64, argus]
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `RUNNER_URL` | `https://github.com/Noah-Bozkurt` | Organization or repository URL to register against |
| `RUNNER_SCOPE` | `org` | `org` or `repo` |
| `RUNNER_NAME_PREFIX` | `argus-runner` | Prefix for automatically generated runner names |
| `RUNNER_NAME` | unset | Optional fixed runner name; avoid this when scaling |
| `RUNNER_LABELS` | `argus,docker` | Comma-separated custom labels |
| `RUNNER_GROUP` | unset | Optional organization runner group |
| `RUNNER_EPHEMERAL` | `false` | Register the runner for one job only |
| `RUNNER_DISABLE_UPDATE` | `false` | Disable the runner's built-in self-update |
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
