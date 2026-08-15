#!/usr/bin/env bash
# The dead-man's switch, rsynced to /srv/ond by `mise run deploy:api` and installed
# to /usr/local/bin by the same task.
#
# Every alert this project has runs on the box it is watching. That is fine for
# the failures the box survives and useless for the ones it does not: a stopped
# instance, a full disk, a Prometheus in the restart loop a malformed rule file
# puts it in. In all three the rules stop being evaluated, and a rule that is
# not evaluated looks exactly like a rule that is not firing.
#
# So the signal is inverted. This publishes a heartbeat to CloudWatch while the
# monitoring stack is healthy, and a CloudWatch alarm with
# `treat_missing_data = "breaching"` fires when the heartbeat *stops*. Nothing
# on this box has to be alive for that alarm to go off — which is the entire
# point, and the one property an on-box alert can never have.
#
# Credentials come from the instance profile, the same way the backup and the
# assistant's Bedrock calls do. There is no key here either.
set -euo pipefail

# Passed in rather than written here. The alarm that watches for this metric's
# silence is declared in infra/main.tf, and a namespace spelled differently in
# the two places would produce an alarm permanently in INSUFFICIENT_DATA beside
# a script permanently reporting success — the two halves of a dead-man's switch
# failing in the one way that looks like nothing is wrong. cron.d/ond.tmpl is
# rendered from the same OpenTofu locals the alarm reads.
readonly NAMESPACE="${1:?usage: heartbeat.sh <namespace> <metric>}"
readonly METRIC="${2:?usage: heartbeat.sh <namespace> <metric>}"

# Both halves of the delivery chain, not just Prometheus. A live Prometheus
# behind a dead Alertmanager evaluates every rule correctly and tells nobody,
# which from the outside is indistinguishable from a healthy quiet system —
# the failure this whole script exists to make visible.
curl -sf --max-time 10 http://127.0.0.1:9090/-/healthy > /dev/null
curl -sf --max-time 10 http://127.0.0.1:9093/-/healthy > /dev/null

# Reached only when both answered. Failing earlier under `set -e` withholds the
# heartbeat, which is how this reports rather than by publishing a zero: a zero
# is a value that needs delivering, and a box that cannot deliver it is exactly
# the case being tested for.
aws cloudwatch put-metric-data \
  --namespace "$NAMESPACE" \
  --metric-name "$METRIC" \
  --value 1
