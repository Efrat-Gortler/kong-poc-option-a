#!/usr/bin/env bash
# Installs / upgrades option A with plain Helm - the way a real CD pipeline would (no Argo CD).
#   scripts/deploy.sh cp       Postgres + control plane (Admin API, Kong Manager, cluster listener) in konga-cp
#   scripts/deploy.sh leg1     data plane + per-leg Redis + backends in konga-leg1      (step B4, not built yet)
#   scripts/deploy.sh leg2     same for konga-leg2                                       (step B4, not built yet)
# Prerequisite once: scripts/bootstrap.sh (namespaces, Secrets).
# Upgrades: helm runs `kong migrations up` (pre-upgrade hook) and `kong migrations finish` (post-upgrade hook);
# take a backup first (docs/OPTION-A-DESIGN.md, "Upgrades in DB mode").
source "$(dirname "$0")/lib.sh"
need helm oc
target="${1:?usage: $0 <cp|leg1|leg2>}"
VALUES="$REPO_ROOT/values"

helm repo list 2>/dev/null | grep -q "^kong\s" || helm repo add kong "$KONG_CHART_REPO" >/dev/null
helm repo update kong >/dev/null

kong_release() { # release namespace values-files...
  local release=$1 ns=$2; shift 2
  local args=()
  for f in "$VALUES/kong-common.yaml" "$@" "$VALUES/platform-$PLATFORM.yaml"; do [[ -f "$f" ]] && args+=(-f "$f"); done
  log "helm upgrade --install $release kong/kong $KONG_CHART_VERSION -n $ns"
  helm upgrade --install "$release" kong/kong --version "$KONG_CHART_VERSION" -n "$ns" \
    --skip-crds "${args[@]}" --wait --timeout 10m
}

case "$target" in
  cp)
    oc get secret konga-postgres -n "$CP_NS" >/dev/null 2>&1 || die "run scripts/bootstrap.sh first"
    log "helm upgrade --install konga-postgres charts/postgres -n $CP_NS"
    helm upgrade --install konga-postgres "$REPO_ROOT/charts/postgres" -n "$CP_NS" \
      --set global.platform="$PLATFORM" --wait --timeout 5m
    kong_release konga-cp "$CP_NS" "$VALUES/cp.yaml" "$VALUES/cp-$PLATFORM.yaml"
    if [[ "$PLATFORM" == openshift ]]; then
      for r in kong-manager kong-admin; do
        log "$r: https://$(oc get route "$r" -n "$CP_NS" -o jsonpath='{.spec.host}')   (free mode: NO login)"
      done
    fi
    ;;
  leg1|leg2)
    ns="konga-$target"
    oc get secret konga-route-redis -n "$ns" >/dev/null 2>&1 || die "run scripts/bootstrap.sh first"
    [[ -d "$KONG_POC_DIR/charts/redis" ]] || die "KONG_POC_DIR=$KONG_POC_DIR: option C repository not found"
    # the leg's own Redis (route-wide counters), chart reused from option C
    log "helm upgrade --install redis kong-poc/charts/redis -n $ns"
    helm upgrade --install redis "$KONG_POC_DIR/charts/redis" -n "$ns" \
      --set global.platform="$PLATFORM" --set passwordSecret=konga-route-redis \
      --set-string 'legNamespaceLabel.kong-poc/role=leg-a' --wait --timeout 5m
    # echo backends (Services orders / users / reports), chart reused from option C; its file:// dependency is
    # built in a temporary copy so nothing is written into the option C repository
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    cp -r "$KONG_POC_DIR/charts/mock-service" "$KONG_POC_DIR/charts/kong-route-lib" "$tmp/"
    rm -rf "$tmp/mock-service/charts"
    helm dependency build "$tmp/mock-service" >/dev/null
    for c in orders users reports; do
      log "helm upgrade --install $c kong-poc/charts/mock-service -n $ns"
      helm upgrade --install "$c" "$tmp/mock-service" -n "$ns" --set component="$c" \
        --set global.platform="$PLATFORM" --set global.leg="$target" --wait --timeout 5m
    done
    kong_release "konga-$target" "$ns" "$VALUES/dp.yaml" "$VALUES/$target.yaml"
    log "data plane $target: oc port-forward -n $ns svc/konga-$target-kong-proxy 8000:80"
    ;;
  *) die "unknown target $target (cp | leg1 | leg2)" ;;
esac
