#!/usr/bin/env bash
# Example configuration for Kong Manager (workspace "default"), written through the Admin API.
# In option A this configuration lives in the control plane's Postgres - NOT in Git. This script only seeds a
# demo so there is something to look at in Kong Manager (which is read-only in free mode).
# Idempotent: PUT by name (services, routes) and by instance_name (plugins). Everything is tagged option-a-demo.
#   scripts/demo-config.sh            create / update
#   scripts/demo-config.sh delete     remove everything tagged option-a-demo
# ADMIN_URL defaults to the Admin API Route (free mode: no credentials).
source "$(dirname "$0")/lib.sh"
need curl jq
ADMIN_URL="${ADMIN_URL:-https://kong-admin-konga-cp.apps-crc.testing}"
TAG=option-a-demo

api() { # method path [json]
  local out code
  out="$(curl -sk -w '\n%{http_code}' -X "$1" "$ADMIN_URL$2" ${3:+-H 'Content-Type: application/json' -d "$3"})"
  code="$(tail -n1 <<<"$out")"
  [[ "$code" =~ ^2 ]] || die "$1 $2 -> HTTP $code $(head -n -1 <<<"$out" | jq -c '{message, fields}' 2>/dev/null)"
  head -n -1 <<<"$out"
}

if [[ "${1:-}" == delete ]]; then
  for kind in plugins routes services; do
    for id in $(api GET "/$kind?tags=$TAG&size=1000" | jq -r '.data[].id'); do api DELETE "/$kind/$id" >/dev/null; done
    log "deleted $kind tagged $TAG"
  done
  exit 0
fi

# ---- Gateway Services: the echo backends. Short host names: every data plane resolves them in its own
# namespace (konga-leg1 / konga-leg2), so one configuration serves every leg. Timeouts/retries as in option C.
for s in orders users reports; do
  api PUT "/services/$s" "$(jq -nc --arg s "$s" --arg t "$TAG" '{
      protocol: "http", host: $s, port: 8080, path: "/",
      connect_timeout: 2000, read_timeout: 10000, write_timeout: 10000, retries: 1, tags: [$t]}')" >/dev/null
  log "service  $s -> http://$s:8080"
done

# ---- Routes
route() { # name service methods-json paths-json
  api PUT "/routes/$1" "$(jq -nc --arg s "$2" --argjson m "$3" --argjson p "$4" --arg t "$TAG" '{
      service: {name: $s}, paths: $p, methods: $m, strip_path: false, protocols: ["http", "https"], tags: [$t]}')" >/dev/null
  log "route    $1: $3 $4 -> $2"
}
route orders        orders  null       '["/orders"]'
route orders-create orders  '["POST"]' '["/orders"]'
route users         users   '["GET"]'  '["/users"]'
route reports       reports null       '["/reports"]'

# ---- Plugins
# Route-wide limit PER LEG: one plugin config for all legs; host and password are env-vault references that each
# data plane resolves to its own leg's Redis (values/leg<N>.yaml). database 4: nothing mixes with option C.
rate_limit() { # route per-minute
  api PUT "/plugins/$1-route-limit" "$(jq -nc --arg r "$1" --argjson n "$2" --arg t "$TAG" '{
      name: "rate-limiting", instance_name: ($r + "-route-limit"), route: {name: $r}, tags: [$t],
      config: {minute: $n, limit_by: "service", policy: "redis", fault_tolerant: true, hide_client_headers: false,
               redis: {host: "{vault://env/kong-route-rl-redis-host}", port: 6379,
                       password: "{vault://env/kong-route-rl-redis-password}", database: 4}}}')" >/dev/null
  log "plugin   rate-limiting on route $1: $2/minute per leg"
}
rate_limit orders 5
rate_limit users 20

# Block everyone on one route
api PUT "/plugins/reports-blocked-everyone" "$(jq -nc --arg t "$TAG" '{
    name: "request-termination", instance_name: "reports-blocked-everyone", route: {name: "reports"}, tags: [$t],
    config: {status_code: 403, message: "blocked: everyone on this route"}}')" >/dev/null
log "plugin   request-termination 403 on route reports"

log "done: $(api GET "/services?tags=$TAG" | jq '.data|length') services, $(api GET "/routes?tags=$TAG" | jq '.data|length') routes, $(api GET "/plugins?tags=$TAG" | jq '.data|length') plugins tagged $TAG"
