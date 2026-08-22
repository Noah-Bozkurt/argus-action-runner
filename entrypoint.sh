#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[argus-runner] %s\n' "$*"
}

fatal() {
  printf '[argus-runner] error: %s\n' "$*" >&2
  exit 1
}

RUNNER_URL="${RUNNER_URL:-https://github.com/Noah-Bozkurt}"
RUNNER_SCOPE="${RUNNER_SCOPE:-org}"
RUNNER_NAME="${RUNNER_NAME:-${RUNNER_NAME_PREFIX:-argus-runner}-${HOSTNAME:-unknown}}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LABELS="${RUNNER_LABELS:-argus,docker}"
RUNNER_GROUP="${RUNNER_GROUP:-}"
RUNNER_EPHEMERAL="${RUNNER_EPHEMERAL:-false}"
RUNNER_DISABLE_UPDATE="${RUNNER_DISABLE_UPDATE:-false}"

cfg_pat=""
if [[ -n "${RUNNER_CFG_PAT_FILE:-}" ]]; then
  [[ -r "${RUNNER_CFG_PAT_FILE}" ]] || fatal "RUNNER_CFG_PAT_FILE is not readable"
  cfg_pat="$(<"${RUNNER_CFG_PAT_FILE}")"
elif [[ -n "${RUNNER_CFG_PAT:-}" ]]; then
  cfg_pat="${RUNNER_CFG_PAT}"
fi

registration_token="${RUNNER_TOKEN:-}"

# Never expose registration credentials to workflow processes.
unset RUNNER_CFG_PAT RUNNER_CFG_PAT_FILE RUNNER_TOKEN

slug="${RUNNER_URL#https://github.com/}"
slug="${slug%/}"
slug="${slug%.git}"

case "${RUNNER_SCOPE}" in
  org)
    [[ "${slug}" != */* ]] || fatal "org scope expects RUNNER_URL like https://github.com/OWNER"
    api_base="https://api.github.com/orgs/${slug}/actions/runners"
    ;;
  repo)
    [[ "${slug}" == */* ]] || fatal "repo scope expects RUNNER_URL like https://github.com/OWNER/REPO"
    api_base="https://api.github.com/repos/${slug}/actions/runners"
    ;;
  *)
    fatal "RUNNER_SCOPE must be 'org' or 'repo'"
    ;;
esac

request_runner_token() {
  local kind="$1"
  [[ -n "${cfg_pat}" ]] || return 1

  curl -fsSL -X POST \
    -H 'Accept: application/vnd.github+json' \
    -H "Authorization: Bearer ${cfg_pat}" \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    "${api_base}/${kind}" | jq -er '.token'
}

if [[ ! -f .runner ]]; then
  if [[ -z "${registration_token}" ]]; then
    [[ -n "${cfg_pat}" ]] || fatal "provide RUNNER_CFG_PAT_FILE, RUNNER_CFG_PAT, or a one-time RUNNER_TOKEN"
    log "requesting registration token"
    registration_token="$(request_runner_token registration-token)"
  fi

  config_args=(
    --url "${RUNNER_URL}"
    --token "${registration_token}"
    --name "${RUNNER_NAME}"
    --work "${RUNNER_WORKDIR}"
    --labels "${RUNNER_LABELS}"
    --unattended
    --replace
  )

  if [[ -n "${RUNNER_GROUP}" ]]; then
    config_args+=(--runnergroup "${RUNNER_GROUP}")
  fi
  if [[ "${RUNNER_EPHEMERAL}" == "true" ]]; then
    config_args+=(--ephemeral)
  fi
  if [[ "${RUNNER_DISABLE_UPDATE}" == "true" ]]; then
    config_args+=(--disableupdate)
  fi

  log "registering ${RUNNER_NAME} at ${RUNNER_URL}"
  ./config.sh "${config_args[@]}"
else
  log "using existing runner registration for ${RUNNER_NAME}"
fi

# The one-hour registration token is not needed after configuration.
registration_token=""

runner_pid=""
cleanup_started=false
cleanup() {
  local exit_code=$?

  if [[ "${cleanup_started}" == "true" ]]; then
    return
  fi
  cleanup_started=true
  trap - EXIT INT TERM

  if [[ -n "${runner_pid}" ]] && kill -0 "${runner_pid}" 2>/dev/null; then
    kill -TERM "${runner_pid}" 2>/dev/null || true
    wait "${runner_pid}" 2>/dev/null || true
  fi

  if [[ -n "${cfg_pat}" && -f .runner ]]; then
    log "deregistering ${RUNNER_NAME}"
    if remove_token="$(request_runner_token remove-token 2>/dev/null)"; then
      ./config.sh remove --unattended --token "${remove_token}" >/dev/null 2>&1 || true
    else
      log "warning: could not obtain a removal token; GitHub may temporarily show the runner offline"
    fi
  fi

  exit "${exit_code}"
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

log "starting runner"
./run.sh &
runner_pid=$!
wait "${runner_pid}"
