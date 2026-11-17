#!/usr/bin/env bash
# Shared helpers for the scripts in this folder. Source it, don't run it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Kong chart and namespaces of option A (pinned; change here, then scripts/deploy.sh <target>)
KONG_CHART_REPO=https://charts.konghq.com
KONG_CHART_VERSION=3.4.1
CP_NS=konga-cp
DP_NAMESPACES=(konga-leg1 konga-leg2)
GSLB_NS=konga-gslb
PLATFORM="${PLATFORM:-openshift}"          # openshift | kubernetes

if ! command -v oc >/dev/null 2>&1; then oc() { kubectl "$@"; }; fi

# Optional: copy everything a script prints into a log file:  export POC_LOG_DIR=~/poc-logs
if [[ -n "${POC_LOG_DIR:-}" && -z "${_POC_LOGGING:-}" ]]; then
  export _POC_LOGGING=1
  mkdir -p "$POC_LOG_DIR"
  exec > >(tee -a "$POC_LOG_DIR/option-a-$(basename "$0" .sh).log") 2>&1
  printf '\n===== %s  %s %s\n' "$(date -Is)" "$(basename "$0")" "$*"
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
need() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done; }

# Ask before anything cluster-wide or destructive. ASSUME_YES=1 skips the prompt.
confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  read -r -p "$1 [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]]
}

random_secret() { openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-32; }
