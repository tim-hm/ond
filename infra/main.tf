# One box, deliberately: API + Postgres + Caddy under Docker Compose on a
# single Graviton instance, data on its own EBS volume, nightly dumps to S3.
# The instance is disposable — everything it runs arrives via `mise run deploy:api`
# (image over SSH, compose files via rsync), and everything worth keeping lives
# on the data volume or in the bucket. RDS is the graduation path, not the
# starting point: at V1 scale it buys nothing a dump schedule doesn't.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# The instance and its data volume must land in the same availability zone, and
# the subnet is what decides. Reading the AZ off the subnet rather than off the
# instance is load-bearing: it lets the volume be built before the instance, so
# the instance's cloud-init can name the volume it is waiting for. The other
# direction is a dependency cycle.
data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  # Canonical's AWS publisher account.
  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

# There is no ingress rule for 22/tcp and there is not meant to be — which is
# not the same as saying the box has no SSH. sshd still listens, and
# `mise run deploy:api` still uses it; the connection simply arrives over the
# tailnet, decapsulated from WireGuard on tailscale0, and a security group
# filters the ENI rather than the tunnel that terminates behind it. So the
# port is unreachable from the internet and reachable from every device on the
# tailnet, with no rule here describing either fact.
#
# Tailscale needs nothing inbound to make that work: it dials out to establish
# the link, and falls back to a DERP relay when NAT refuses a direct path.
# `all-all` egress is what it depends on.
module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "ond-api"
  description = "HTTP(S) from everywhere; nothing else, SSH arrives over the tailnet"
  vpc_id      = data.aws_vpc.default.id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      # Caddy answers 80 only to redirect to HTTPS and to solve ACME challenges.
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_rules = ["all-all"]
}

module "backups" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "ond-backups-"

  # A nightly dump holds the whole `users` table, and under this identity model
  # every `users.id` *is* the bearer credential for that person's profile,
  # journey and entitlement — so this bucket takes the same hardening the state
  # bucket takes in bootstrap/main.tf, stated rather than inherited. The module's
  # v4 defaults already block public access and AWS encrypts new buckets by
  # default; writing both out is what stops an upstream default changing under a
  # major version bump from silently relaxing the more sensitive of the two
  # buckets. No `prevent_destroy` to match, though: dumps expire at 30 days by
  # design, so this bucket is reproducible in a way state never is.
  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
      bucket_key_enabled = true
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # The dump crosses the public internet from the box's `aws s3 cp`; refusing
  # plaintext transport is the same cheap insurance bootstrap takes on state.
  attach_deny_insecure_transport_policy = true

  # Dumps are worthless past the point anyone would restore them; 30 days keeps
  # the bucket from quietly accumulating forever. Both of the other two clauses
  # exist to keep that 30 honest:
  #
  # Versioning turns `expiration` into a delete marker rather than a delete, so
  # without a noncurrent rule the bytes would stay for ever and the number above
  # would be fiction. One day, not thirty — the current-version expiry *is* the
  # retention policy, and the noncurrent window only has to outlast a mistaken
  # delete.
  #
  # The cron pipes `pg_dump | gzip | aws s3 cp -` from stdin, which is always a
  # multipart upload, so a reboot or a dropped link mid-dump strands parts that
  # are billed as storage and are invisible to both expiry rules.
  lifecycle_rule = [
    {
      id      = "expire-dumps"
      enabled = true
      expiration = {
        days = 30
      }
      noncurrent_version_expiration = {
        days = 1
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

# The instance may write backups and nothing else — no keys on the box, just
# the instance profile.
# Loki's chunk store.
#
# Its own bucket rather than a prefix in the backups one, on the grounds that
# the two hold different things and want different rules: a dump is every row
# the product has and takes versioning and a deny on insecure transport; logs
# are high-volume, rewritten constantly by the compactor, and versioning them
# would keep every superseded chunk for the length of the retention it is
# supposed to enforce.
#
# On S3 rather than the data volume because that volume is the one Postgres
# writes to, and because logs that die with the instance are logs that are
# missing exactly when the instance is what failed.
module "logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket_prefix = "ond-logs-"

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
      bucket_key_enabled = true
    }
  }

  # Belt as well as Loki's own compactor. `retention_period` in loki.yaml is
  # what actually deletes, and it only runs because the compactor is explicitly
  # enabled — a config that quietly stops honouring it would otherwise grow this
  # bucket for ever. Thirty-five days, a little past Loki's thirty, so the
  # lifecycle is the backstop and not the thing racing the compactor.
  lifecycle_rule = [
    {
      id      = "expire"
      enabled = true
      expiration = {
        days = 35
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "write_backups" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${module.backups.s3_bucket_arn}/*"]
  }

  # Reading back what was written. `PutObject` alone was enough while nothing
  # ever checked, which is precisely how a nightly dump of the wrong database
  # went unnoticed for eight days — the operator could not `aws s3 ls` from the
  # box to see what had actually landed. Verification needs the read side.
  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.backups.s3_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.backups.s3_bucket_arn}/*"]
  }
}

# Loki's own access, and it needs more than the backup does: the compactor
# rewrites and deletes index objects, so read, write and delete are all real
# rather than a convenience. Scoped to this one bucket for the same reason every
# other grant here is — the instance role is what an SSRF in anything on this
# box would be reaching for.
data "aws_iam_policy_document" "store_logs" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.logs.s3_bucket_arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${module.logs.s3_bucket_arn}/*"]
  }
}

# Where every alert ends up, from both directions: Alertmanager publishes the
# Prometheus rules here, and the CloudWatch alarms below publish the two
# failures Prometheus cannot see because it is inside them.
#
# One topic rather than one per severity. Fan-out belongs to the subscriptions —
# adding an SMS subscription filtered to `severity: critical` later needs no
# change on the box, which is why Alertmanager stamps that attribute already.
resource "aws_sns_topic" "alarms" {
  name = "ond-alarms"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# The box's half of the alert path. Scoped to this one topic for the same reason
# the Bedrock grant is scoped to one profile: this role is what an SSRF in
# anything running here would be reaching for, and `sns:Publish` on `*` is a
# spam relay.
data "aws_iam_policy_document" "publish_alarms" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
  }
}

# The heartbeat. `PutMetricData` takes no resource ARN — CloudWatch has no
# per-metric ARN to name — so the condition on the namespace is the only thing
# that bounds this, and without it the grant is "write any metric in the
# account".
data "aws_iam_policy_document" "put_metrics" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [local.heartbeat_namespace]
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # The CloudWatch namespace and metric heartbeat.sh publishes into, and the
  # alarm below watches for silence in. Written once here because three things
  # have to agree on it — the IAM condition that bounds what the box may write,
  # the alarm's dimensions, and the script itself — and two of the three are in
  # this file.
  heartbeat_namespace = "Ond"
  heartbeat_metric    = "MonitoringHeartbeat"

  # The foundation model behind the inference profile: the same id with the
  # geography prefix taken off, because that prefix is the profile and not part
  # of the model's name. Derived rather than written out a second time — two
  # literals naming one model is a pair that can disagree, and the way it would
  # disagree is an AccessDenied at invoke time.
  #
  # The optional group matches `eu.`, `us.`, `apac.` and anything else shaped
  # like a geography, and leaves a profile id carrying no prefix alone.
  assistant_foundation_model = regex("^(?:[a-z]{2,4}\\.)?(.*)$", var.assistant_inference_profile)[0]
}

# The assistant's model calls. Scoped to one profile and one model rather than
# `bedrock:*` on `*`, because this role is what an SSRF in anything the box runs
# would be reaching for.
#
# Both ARN families are load-bearing and the second one is the trap. Invoking a
# cross-region inference profile is authorised twice: once against the profile,
# which is where the call is addressed, and once against the underlying
# foundation model in whichever destination region Bedrock forwards it to. A
# policy naming only the profile is accepted by a plan, applies cleanly, and
# then fails every call with AccessDenied — in production, because that is the
# first place a real invocation happens.
#
# `var.assistant_profile_regions` therefore has to be the profile's *complete*
# destination list, not the regions we expect to be used: a region left out is a
# failure that appears only when Bedrock happens to route there under load.
data "aws_iam_policy_document" "invoke_model" {
  statement {
    actions = [
      "bedrock:InvokeModel",
      # Not optional: the chat RPC streams, so this is the action the coach
      # actually uses on the path a person watches.
      "bedrock:InvokeModelWithResponseStream",
    ]

    resources = concat(
      # System-defined inference profiles are account-scoped and live in the
      # region the call is signed for — the box's own.
      ["arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.assistant_inference_profile}"],
      # Foundation models are not account-scoped, hence the empty account field.
      [for destination in var.assistant_profile_regions :
        "arn:aws:bedrock:${destination}::foundation-model/${local.assistant_foundation_model}"
      ],
    )
  }
}

resource "aws_iam_role" "api" {
  name               = "ond-api"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy" "write_backups" {
  name   = "write-backups"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.write_backups.json
}

resource "aws_iam_role_policy" "invoke_model" {
  name   = "invoke-model"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.invoke_model.json
}

resource "aws_iam_role_policy" "publish_alarms" {
  name   = "publish-alarms"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.publish_alarms.json
}

resource "aws_iam_role_policy" "put_metrics" {
  name   = "put-metrics"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.put_metrics.json
}

resource "aws_iam_role_policy" "store_logs" {
  name   = "store-logs"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.store_logs.json
}

# The everyday dev loop's identity. `mise run dev` idles all day holding
# credentials in order to call exactly one API, and before this role the
# credentials it held were the `ond-tofu` user's AdministratorAccess. A role
# assumable by that user alone, rather than a second user, so the laptop keeps
# one set of long-lived keys — and the process that sits open all day signs as
# something that can invoke Bedrock and do nothing else.
data "aws_iam_user" "tofu" {
  # Must match `tofu_user_name` in infra/bootstrap/variables.tf. Bootstrap keeps
  # local state, so there is no remote-state output to read the name from — two
  # literals that have to agree, like the Caddyfile hostname and the Route 53
  # record. A rename fails this lookup at plan time; a *recreated* user does
  # not — IAM stores the trust principal as the old user's unique id, so
  # re-running bootstrap leaves this role unassumable until the next apply
  # rewrites the trust policy it plans as unchanged-looking.
  user_name = "ond-tofu"
}

data "aws_iam_policy_document" "assume_dev" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_user.tofu.arn]
    }
  }
}

resource "aws_iam_role" "dev" {
  name               = "ond-dev"
  assume_role_policy = data.aws_iam_policy_document.assume_dev.json
}

# The same policy document the box's role carries — one definition of who may
# call Bedrock, worn by two principals. A dev-only copy would be a pair free to
# drift, and the way it would drift is a laptop that can reach a model the
# deployment cannot.
resource "aws_iam_role_policy" "dev_invoke_model" {
  name   = "invoke-model"
  role   = aws_iam_role.dev.id
  policy = data.aws_iam_policy_document.invoke_model.json
}

# Break-glass, and load-bearing now in a way it was not before. With 22/tcp
# closed the tailnet is the only route to a shell, so every way the tailnet can
# fail — an expired node key, an auth key spent before a rebuild, a `tailscale
# up` that never ran because cloud-init died at an earlier step — is a way to be
# locked out of the box entirely. Session Manager reaches it through the
# instance profile over the same outbound path, needing no port, no key and
# nothing on the tailnet to be working.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "api" {
  name = "ond-api"
  role = aws_iam_role.api.name
}

resource "aws_key_pair" "admin" {
  key_name   = "ond-admin"
  public_key = var.ssh_public_key
}

locals {
  # The name the box registers on the tailnet under, and so the name MagicDNS
  # answers for it — which is how `mise run deploy:api` and the restore command find
  # it now that no public address reaches 22/tcp. Defined once and read by both
  # the cloud-init template and the `ssh_host` output, because the box
  # announcing one name while deploy dials another is a lockout with no error
  # message on the box's side.
  #
  # Tailscale appends `-1` when a name is already taken, so a second node called
  # this would answer to something else and leave deploy pointing at the first.
  tailscale_hostname = "ond-api"
}

module "instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name = "ond-api"

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [module.security_group.security_group_id]
  key_name               = aws_key_pair.admin.key_name
  iam_instance_profile   = aws_iam_instance_profile.api.name

  # `backup_bucket` and `region` used to be here for the backup cron this file
  # no longer writes. They are gone rather than left unused: the bucket now
  # reaches the box through `mise run deploy:api`, which renders it from the output
  # of the same resource, so first boot has no opinion about backups at all.
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    tailscale_auth_key = var.tailscale_auth_key
    tailscale_hostname = local.tailscale_hostname
    # Nitro ignores the /dev/sdf attachment name and enumerates volumes as
    # unpredictable /dev/nvme*n1, but udev also names each one by its EBS volume
    # ID — with the dash stripped, because that is what the NVMe serial field
    # holds. Resolving the path here rather than probing for it on the box means
    # first boot looks for one exact device instead of guessing.
    data_device = "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.data.id, "-", "")}"
  })

  # cloud-init formats and mounts the data volume by label on first boot; a
  # user_data change must not silently rebuild the box out from under it.
  #
  # The corollary is the trap in every tailnet change made from here: a new auth
  # key plans as an in-place user_data update, applies in seconds, and does
  # nothing at all to the running instance, whose cloud-init finished long ago.
  # This file describes how the *next* box joins. Joining the current one is the
  # `tailscale up` in docs/deployment.md, run over SSM.
  user_data_replace_on_change = false

  # The module's volume_tags apply to every volume attached to the instance,
  # including the data volume, which is a separate resource carrying its own
  # Name. Left on, the two rewrite that tag past each other and every plan shows
  # a change that no apply ever settles — which is how operators learn to skim
  # plans instead of reading them.
  enable_volume_tags = false

  # IMDSv2 only — an unauthenticated metadata endpoint is reachable from any
  # SSRF in anything the box runs, and it hands out the instance profile's
  # credentials. hop_limit 2 rather than the default 1 because the containers sit
  # one network hop away behind Docker's bridge, and the backup cron's
  # `aws s3 cp` reads its credentials from exactly this endpoint.
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # The AMI's own default is 8 GiB and unencrypted. 8 GiB does not survive
  # `docker save | docker load` cycles accumulating images alongside the build
  # cache. Both attributes are ForceNew, so they are cheap now and cost an
  # instance replacement later.
  root_block_device = {
    size      = 20
    type      = "gp3"
    encrypted = true
  }
}

# Postgres data lives here, not on the root volume, so replacing the instance
# replaces nothing that matters — with one exception. Caddy's certificates are
# in a docker volume on the root disk, so a rebuild re-issues them;
# infra/box/compose.yaml says why that is left alone.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_gb
  type              = "gp3"
  # Every row the product has, at rest. ForceNew, so turning it on later means
  # snapshot, restore, reattach — not an edit.
  encrypted = true

  tags = {
    Name = "ond-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = module.instance.id
}

# Daily snapshots of the data volume.
#
# Not a second database backup — the nightly `pg_dump` is that, and it stays the
# path a restore should take, because an EBS snapshot of a running Postgres is
# crash-consistent rather than clean: it comes back and WAL-replays, which
# usually works and is not a thing to find out about during an incident.
#
# What this covers is everything the dump does not, and until now nothing did:
# the Prometheus TSDB, Grafana's database, Alertmanager's silences, and the
# ability to rebuild the box without starting from an empty disk. Losing the
# volume used to mean losing all of it silently.
#
# Snapshots are incremental after the first, so seven dailies of a
# mostly-static volume cost roughly a coffee a month.
resource "aws_dlm_lifecycle_policy" "data" {
  # ASCII only, and not a style choice: DLM validates this field against
  # `[0-9A-Za-z _-]+` and rejects the o-umlaut in "önd" at apply time.
  description        = "Daily snapshots of the ond data volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    # By tag rather than by id, so replacing the volume does not silently leave
    # the policy pointing at something that no longer exists.
    target_tags = {
      Name = "ond-data"
    }

    schedule {
      name = "daily"

      create_rule {
        # 03:30 UTC — after the 02:17 dump has finished and released its temp
        # file, so the snapshot captures a volume at rest rather than one being
        # read end to end.
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:30"]
      }

      retain_rule {
        count = var.backup_snapshot_retention
      }

      copy_tags = true
    }
  }
}

data "aws_iam_policy_document" "assume_dlm" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "ond-dlm"
  assume_role_policy = data.aws_iam_policy_document.assume_dlm.json
}

# AWS's own managed policy for the service. Hand-writing the equivalent would be
# enumerating the snapshot API surface and keeping up with it, which is exactly
# the maintenance the managed policy exists to absorb — and unlike the instance
# role, this one is assumable only by the DLM service, so there is no box to
# reach it from.
resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# A stable address to hang the DNS A record on: the instance can be rebuilt
# without touching DNS.
resource "aws_eip" "api" {
  instance = module.instance.id
  domain   = "vpc"
}

# DNS. The zone lives here rather than at the registrar so the record and the
# address it points at are applied together — that pairing was the one manual
# step in a launch, and a record left pointing at a released address is a
# failure nothing in this repo could have caught. The registrar keeps only the
# NS delegation, which is set once and never again.
#
# The name must also match the site block in infra/box/Caddyfile. Caddy's
# config is rsynced as a static file rather than rendered, so neither side can
# derive the other; they are two literals that have to agree, and the Caddyfile
# says so too.
resource "aws_route53_zone" "primary" {
  name = "ondbreathe.app"
}

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = aws_route53_zone.primary.name
  type    = "A"
  # Short, because the value worth changing quickly is exactly this one: an
  # elastic IP means the record is stable in normal operation, so the only time
  # it moves is the time somebody is waiting on it.
  ttl     = 300
  records = [aws_eip.api.public_ip]
}

# The only thing watching this service from outside it.
#
# Everything else in this project's monitoring runs on the box it monitors, and
# that is fine for the failures the box survives and worthless for the ones it
# does not. It also cannot see the failure this project has actually had:
# `tailscale serve` taking 443, after which Caddy loses its bind and ends up
# running with no network attached — `docker ps` says up, Prometheus reports
# every container healthy, and the site answers nothing. Not one of the rules in
# alerts.yml can fire on that, because from inside the box nothing is wrong.
#
# `HTTPS_STR_MATCH` rather than a plain status check, and the string is the
# reason: the Caddyfile serves the marketing site as a fallback for anything the
# API allowlist does not match, so a routing regression can answer 200 with an
# HTML page. Matching on the health payload means a 200 from the wrong handler
# fails the check, which a status-only probe would pass.
resource "aws_route53_health_check" "public" {
  type              = "HTTPS_STR_MATCH"
  fqdn              = aws_route53_zone.primary.name
  port              = 443
  resource_path     = "/health"
  search_string     = "ok"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "ond-public"
  }
}

# Route 53 publishes health-check metrics into us-east-1 and nowhere else, so
# the alarm reading them has to be created there whatever region the rest of
# this lives in. An alarm built against the default provider applies cleanly and
# then sits in INSUFFICIENT_DATA for ever — a monitor that looks configured and
# watches nothing, which is worse than an absent one.
resource "aws_cloudwatch_metric_alarm" "public_unhealthy" {
  provider = aws.us_east_1

  alarm_name          = "ond-public-unhealthy"
  alarm_description   = "https://ondbreathe.app/health has stopped answering from outside the box."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.public.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms_us_east_1.arn]
  ok_actions    = [aws_sns_topic.alarms_us_east_1.arn]
}

# The second topic, and it exists for one reason: a CloudWatch alarm may only
# publish to an SNS topic in its own region, and the alarm above is pinned to
# us-east-1 by where Route 53 puts its metrics. SNS cannot subscribe to SNS, so
# there is no way to funnel this into the main topic without a Lambda, which is
# a great deal of machinery to avoid one extra confirmation click.
#
# The cost is that `tofu apply` sends *two* subscription confirmations on first
# run and both must be clicked. An unconfirmed subscription accepts every
# publish and silently drops it, so a half-confirmed pair looks exactly like a
# working one until the day it matters.
resource "aws_sns_topic" "alarms_us_east_1" {
  provider = aws.us_east_1
  name     = "ond-alarms"
}

resource "aws_sns_topic_subscription" "alarms_us_east_1_email" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alarms_us_east_1.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# The dead-man's switch, and the only alert here that fires on silence.
#
# heartbeat.sh publishes while Prometheus *and* Alertmanager both answer, every
# five minutes. `treat_missing_data = "breaching"` turns the absence of that
# into an alarm, which is the only construction that can report a box that has
# stopped, a disk that has filled, or a Prometheus crash-looping on a rule file
# that does not parse — `check:alerts` exists because that last one is a real
# way to lose monitoring, and until now losing it looked exactly like nothing
# firing.
#
# Three periods before it trips: one missed heartbeat is a slow metadata lookup.
# Region matters here only in that it does not have to: this metric is written
# by heartbeat.sh, which signs for the box's own region, so the alarm sits
# beside the main topic and needs no second subscription. The Route 53 alarm
# above is the exception, and only because AWS chooses where those metrics live.
resource "aws_cloudwatch_metric_alarm" "monitoring_silent" {
  alarm_name          = "ond-monitoring-silent"
  alarm_description   = "The box has stopped reporting that its monitoring stack is alive."
  namespace           = local.heartbeat_namespace
  metric_name         = local.heartbeat_metric
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms_us_east_1.arn]
  ok_actions    = [aws_sns_topic.alarms_us_east_1.arn]
}

# Mail for the domain, and the four records that authenticate it. Every value
# here belongs to one Google Workspace tenant — see docs/deployment.md before
# applying this into a fresh account.

# The apex TXT set. DNS keeps one TXT set per name, so every apex string lives in
# the list below: a second `aws_route53_record` at this name does not add to this
# one, it fights it. Only one string may start `v=spf1` — two SPF policies is a
# `permerror`, which receivers treat as no policy at all.
#
# Google re-checks the verification token rather than reading it once, so
# deleting it after enrolment un-verifies the domain.
resource "aws_route53_record" "apex_txt" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = aws_route53_zone.primary.name
  type    = "TXT"
  ttl     = 3600
  records = [
    "google-site-verification=ytC4-ZAJ7dO3fLsV52iJmQDu8h27cLFsmFcLHrwgCdg",
    # `~all` rather than `-all`: forwarding breaks SPF by design, because a
    # forwarder relays under its own address. A hard fail rejects that mail.
    "v=spf1 include:_spf.google.com ~all",
  ]
}

# One host at priority 1, not the five ASPMX records older guides still give:
# Google replaced that set, and running both generations of it delivers to two
# places at once.
resource "aws_route53_record" "apex_mx" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = aws_route53_zone.primary.name
  type    = "MX"
  ttl     = 3600
  records = ["1 smtp.google.com."]
}

# The public half of the key Google signs outgoing mail with, under the selector
# named in a signature's `s=` tag.
#
# One key split across two strings: a DNS character-string caps at 255 bytes and
# this key's base64 runs to 408, so the `""` in the middle is a real boundary,
# not a typo. A resolver concatenates adjacent strings before any verifier parses
# them.
resource "aws_route53_record" "google_domainkey" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "google._domainkey.${aws_route53_zone.primary.name}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DKIM1;k=rsa;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsn5him2Gh5VlT5TgFPytX39+sK9LWweR0ptYpKwkWELZrDJBGVil2ChdVKciIva5HkRUghEdqnBjEl4fSh5qZZYmePE6MvM+AWQ2KrUSU0reHvWXjZZZUzfkHzp7doUc8rw/AKfizCU4KOdVujNqHrp7rAdbxJCu2FKeSO0OMfIFUrLnhC7d1X3mnDRyeXDdq26\"\"LzDtUoArd3SLRvBEcrCq49xvJ2SnnmAodt4cKFqVUxthxe97Hi1k4rCfS3ERhCOhw06Vqtgc/F040rTQ1lBCYZ08AnmnG1lNOi4IQwfNgUfn+t0UGJz4D0weQaLYSaL/4kd/AqsgyX5rHpqj/nQIDAQAB"]
}

# What makes the two records above enforceable: without a policy, a receiver
# holding a failing signature has nothing telling it what to do.
#
# This record does not enforce anything yet, and does not collect anything
# either. `p=none` asks receivers to act on nothing, and with no `rua` there is
# nowhere for them to report to — so today it is a placeholder that reserves the
# name, not a control. That is deliberate on both halves: a policy written before
# anyone has watched a week of traffic rejects the sender somebody forgot about,
# and there is no mailbox in this domain yet to read reports at. An address in
# another domain only receives them if that zone publishes
# `ondbreathe.app._report._dmarc.<their-domain>`, which is why `rua` is not
# simply pointed elsewhere.
#
# Turning it into a control is two edits in order: add `rua` and read the reports
# first, then tighten `p`.
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "_dmarc.${aws_route53_zone.primary.name}"
  type    = "TXT"
  # Short, for the reason the apex A record is short: this is the one record here
  # written to be changed, and tightening a DMARC policy wrong loses mail
  # silently. At 3600 the bad version stands for an hour at every receiver that
  # cached it, and the rollback is stale for another hour.
  ttl     = 300
  records = ["v=DMARC1; p=none"]
}
