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
