#!/usr/bin/env bash
# The nightly database backup, rsynced to /srv/ond and installed to
# /usr/local/bin by `mise run deploy:api`. Replaces a cron pipeline without
# `pipefail`, where a failed pg_dump still uploaded a valid gzip of nothing —
# for eight days, while the lifecycle rotated the last good dump away. So this
# fails loudly, verifies before uploading, and leaves a metric behind.
set -euo pipefail

readonly BUCKET="${1:?usage: backup.sh <bucket>}"
readonly COMPOSE=/srv/ond/compose.yaml
readonly TEXTFILE_DIR=/srv/data/textfile
readonly METRICS="${TEXTFILE_DIR}/backup.prom"

# A dump smaller than this is not a database. The schema alone — every table,
# index and the seeded technique catalogue — compresses to far more than 10 KiB,
# so this cannot trip on a legitimately quiet day; it exists to catch the empty
# and truncated cases that used to upload cleanly.
readonly MIN_BYTES=10240

# /var/tmp is on the root volume, deliberately: staging a copy of the database
# on the volume Postgres writes to is how a backup takes the database down.
# Declared and assigned separately because `readonly x="$(cmd)"` makes the
# assignment the command whose status `set -e` sees, so a failing `mktemp`
# would be swallowed and the script would carry on with an empty path.
WORK="$(mktemp -d /var/tmp/ond-backup.XXXXXX)"
readonly WORK

STAMP="$(date -u +%F)"
readonly STAMP
readonly ARCHIVE="${WORK}/ond-${STAMP}.sql.gz"

started="$(date +%s)"

# The last value this file recorded for a metric, or nothing. write_metrics
# rewrites the file whole, and a failing run must carry the previous success
# forward: the age of `ond_backup_last_success_timestamp_seconds` is what
# BackupStale reads, and deleting it on failure would replace a rule that
# fires in 26 hours with one that fires in 25 days.
previous() {
  [ -f "$METRICS" ] || return 0
  awk -v name="$1" '$1 == name { print $2 }' "$METRICS"
}

# Written through a temp file and renamed, because node-exporter reads this
# directory on a schedule of its own and a half-written file parses as a broken
# exposition rather than as no data.
write_metrics() {
  local outcome="$1" bytes="$2"
  local tmp="${METRICS}.$$"
  local now
  now="$(date +%s)"

  # On failure these keep whatever the last successful run left. On success they
  # are replaced. Either way the three series always exist once one backup has
  # ever worked, which is what lets BackupStale be a rule about age rather than
  # about presence.
  local success_at size duration
  if [ "$outcome" = 1 ]; then
    success_at="$now"
    size="$bytes"
    duration="$(( now - started ))"
  else
    success_at="$(previous ond_backup_last_success_timestamp_seconds)"
    size="$(previous ond_backup_bytes)"
    duration="$(previous ond_backup_duration_seconds)"
  fi

  {
    echo '# HELP ond_backup_last_attempt_timestamp_seconds When the backup last ran, whatever the outcome.'
    echo '# TYPE ond_backup_last_attempt_timestamp_seconds gauge'
    echo "ond_backup_last_attempt_timestamp_seconds ${now}"
    echo '# HELP ond_backup_success Whether the most recent attempt uploaded a verified dump.'
    echo '# TYPE ond_backup_success gauge'
    echo "ond_backup_success ${outcome}"

    if [ -n "$success_at" ]; then
      echo '# HELP ond_backup_last_success_timestamp_seconds When a verified dump last reached S3.'
      echo '# TYPE ond_backup_last_success_timestamp_seconds gauge'
      echo "ond_backup_last_success_timestamp_seconds ${success_at}"
    fi
    if [ -n "$size" ]; then
      echo '# HELP ond_backup_bytes Compressed size of the most recent verified dump.'
      echo '# TYPE ond_backup_bytes gauge'
      echo "ond_backup_bytes ${size}"
    fi
    if [ -n "$duration" ]; then
      echo '# HELP ond_backup_duration_seconds How long the most recent verified backup took.'
      echo '# TYPE ond_backup_duration_seconds gauge'
      echo "ond_backup_duration_seconds ${duration}"
    fi
  } > "$tmp"

  mv "$tmp" "$METRICS"
}

# One handler on EXIT rather than a trap on ERR: `trap ... ERR` does not fire
# on an explicit `exit`, so the size-floor rejection below would leave no
# metric and `ond_backup_success` would keep reporting the previous run's 1.
# It writes 0 even for blameless failures: the question is whether a
# restorable dump exists, and one that failed understandably does not.
finish() {
  local status=$?
  [ "$status" -eq 0 ] || write_metrics 0 0
  rm -rf "$WORK"
}
trap finish EXIT

install -d -m 0755 "$TEXTFILE_DIR"

# Dumped to a file rather than piped, so pg_dump's exit status is checked before
# anything is uploaded. `exec -T` because cron has no TTY.
docker compose -f "$COMPOSE" exec -T db pg_dump -U postgres ond | gzip > "$ARCHIVE"

# Both halves of "is this a real backup", in the order they can fail. `gunzip -t`
# walks the whole stream and checks its CRC, which catches a dump truncated
# mid-write; the size floor catches the one that is intact and empty.
gunzip -t "$ARCHIVE"
bytes="$(stat -c %s "$ARCHIVE")"
if [ "$bytes" -lt "$MIN_BYTES" ]; then
  echo "backup: ${ARCHIVE} is ${bytes} bytes, below the ${MIN_BYTES} floor — refusing to upload" >&2
  exit 1
fi

# Only now, with a dump that has been read back and measured.
aws s3 cp "$ARCHIVE" "s3://${BUCKET}/ond-${STAMP}.sql.gz"

write_metrics 1 "$bytes"
echo "backup: uploaded ond-${STAMP}.sql.gz (${bytes} bytes)"
