output "elastic_ip" {
  description = "The box's public address, where 443 and 80 answer and nothing else does. The A record pointing at it is managed here rather than by hand; `dig +short ondbreathe.app` against this value is what says delegation has taken."
  value       = aws_eip.api.public_ip
}

output "ssh_host" {
  description = "Where `mise run deploy` and the restore command find the box: its MagicDNS name on the tailnet, not its public address, because 22/tcp is closed to the internet. Resolvable from any device on the tailnet and from nowhere else — a device that has drifted off the tailnet gets a DNS failure rather than a hang, which is the more legible of the two."
  value       = local.tailscale_hostname
}

output "name_servers" {
  description = "Delegate the domain to these four at the registrar. The only DNS step that stays manual, and it is done once — every record after it is applied from infra/."
  value       = aws_route53_zone.primary.name_servers
}

output "backup_bucket" {
  description = "Where the nightly pg_dump lands."
  value       = module.backups.s3_bucket_id
}

output "alarm_topic_arn" {
  description = "Where Alertmanager publishes. `mise run deploy` renders it into infra/box/alertmanager.yml, so the box learns the ARN from this state rather than from a literal committed beside the config — the arrangement the Caddyfile hostname has with the Route 53 zone, avoided here because there was a way to avoid it."
  value       = aws_sns_topic.alarms.arn
}

output "region" {
  description = "The region the box signs for. Read by `mise run deploy` to render the cron's AWS_DEFAULT_REGION and Alertmanager's sigv4 block, so neither carries a literal that could disagree with the provider."
  value       = var.region
}

output "heartbeat_metric" {
  description = "The CloudWatch namespace and metric name heartbeat.sh publishes into, rendered into the cron by `mise run deploy`. Shared with the alarm that watches for its silence, because a dead-man's switch whose two halves disagree about the metric name reports success and watches nothing."
  value = {
    namespace = local.heartbeat_namespace
    metric    = local.heartbeat_metric
  }
}

output "dev_role_arn" {
  description = "The `role_arn` for the `[profile ond-dev]` stanza `mise run dev` pins — docs/contributing.md shows the stanza."
  value       = aws_iam_role.dev.arn
}
