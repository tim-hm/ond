#!/bin/sh
# Runs on the box as root, rsynced there and invoked by `mise run deploy:api`.
# Everything here must be idempotent: every deploy runs the whole file.
set -eu

# Data directories under /srv/data rather than docker volumes, so a rebuilt
# instance keeps its history. Each is owned by its container's uid; the
# textfile directory stays root-owned because the backup cron writes it as
# root and node-exporter only reads.
install -d -o 65534 -g 65534 /srv/data/prometheus
install -d -o 65534 -g 65534 /srv/data/alertmanager
install -d -o 472 -g 472 /srv/data/grafana
install -d -m 0755 -o root -g root /srv/data/textfile
install -d -o 10001 -g 10001 /srv/data/loki
install -d -o root -g root /srv/data/alloy

# The rsync target deploy:website writes as ubuntu. Created here because
# compose's short mount syntax lets dockerd create a missing bind source as
# root, which the next website deploy could not write.
install -d -o ubuntu -g ubuntu /srv/ond/web

install -m 0755 -o root -g root /srv/ond/backup.sh /srv/ond/heartbeat.sh /usr/local/bin/
install -m 0644 -o root -g root /srv/ond/cron.d/ond /etc/cron.d/ond
# The cron cloud-init wrote on boxes provisioned before it stopped; left in
# place it runs the old unverified backup pipeline alongside the new one.
rm -f /etc/cron.d/ond-backup

cd /srv/ond
docker compose --profile tools run --rm migrate
docker compose up -d --remove-orphans
# These read bind-mounted config that `up -d` cannot see change, so they are
# restarted explicitly — Caddy in particular keeps serving the config it
# parsed at boot, which is a silent routing failure.
docker compose restart caddy prometheus alertmanager loki alloy grafana

# Idempotent, and applied here rather than by cloud-init, which runs once at
# first boot. `--https` is not optional: its default is 443, which Caddy
# holds — that collision has taken the site down once (docs/deployment.md).
tailscale serve --bg --https=29104 3000
tailscale serve --bg --https=29105 9090
tailscale serve --bg --https=29106 9093

# Every deploy loads a new image under the same tag, leaving the previous
# one dangling on a 20 GiB root volume; nothing else ever removes them.
docker image prune -f
