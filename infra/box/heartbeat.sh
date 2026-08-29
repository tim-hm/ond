#!/usr/bin/env bash
# The dead-man's switch, installed by `mise run deploy:api`. On-box alerts die
# with the box, and a rule that is not evaluated looks exactly like one that
# is not firing. So the signal is inverted: this publishes a heartbeat while
# the stack is healthy, and a CloudWatch alarm with `treat_missing_data =
# "breaching"` fires on its silence — nothing on the box has to be alive.
set -euo pipefail

# Passed in rather than written here: the alarm watching this metric's silence
# is declared in infra/main.tf, and a namespace spelled differently in the two
# places leaves an alarm permanently INSUFFICIENT_DATA beside a script
# reporting success — the one failure that looks like nothing is wrong.
# cron.d/ond.tmpl is rendered from the same OpenTofu locals the alarm reads.
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
