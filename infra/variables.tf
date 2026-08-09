variable "region" {
  description = "AWS region. London by default — closest EU-adjacent region to the operator."
  type        = string
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "Graviton (arm64) instance — the Dockerfile builds linux/arm64. t4g.small's 2 GiB is the smallest that leaves Postgres real headroom next to the API and Caddy; micro's 1 GiB does not. Bump here if it stops being enough."
  type        = string
  default     = "t4g.small"
}

variable "ssh_public_key" {
  description = "The operator's SSH public key (the `ssh-ed25519 ...` line). It no longer authorises anything: Tailscale SSH claims port 22 on the tailnet address and the security group closes it on the public one, so the tailnet's `ssh` policy rule is what admits a session and sshd is left listening to nobody. Required all the same, because the key pair is ForceNew on the instance — dropping it would rebuild the box to withdraw a credential that already opens nothing."
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key the box registers with on first boot, from the tailnet's Settings → Keys page. Mint it single-use and tagged `tag:server`: single-use because the key reaches the box in user_data, which anything on the box can read back through IMDS, so a key that is spent by the time cloud-init finishes is a key worth nothing to a reader; tagged because a node registered under a user's own identity inherits that user's key expiry and silently drops off the tailnet months later, taking `mise run deploy` with it, while a tagged node does not expire. Required and undefaulted for the reason `assistant_profile_regions` is: there is no value here that is right on someone else's tailnet."
  type        = string
  sensitive   = true
}

variable "assistant_inference_profile" {
  description = "Bedrock inference profile the coach invokes. Must match BEDROCK_MODEL_ID in crates/api/src/config.rs — two literals naming one model, with nothing reconciling them, the same arrangement the Caddyfile hostname has with the Route 53 record."
  type        = string
  default     = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "assistant_profile_regions" {
  description = "Every destination region of `assistant_inference_profile`, read from its detail page in the Bedrock console. Required and deliberately undefaulted: the IAM policy has to name the underlying foundation model in each one, a guessed list is wrong in a way that only shows up as AccessDenied on a call Bedrock happened to route to the missing region, and a plan that stops for a missing value is a far cheaper place to find that out. It is also what `web/privacy.html` asserts about where coach requests are processed, so it is not a value to infer."
  type        = list(string)
}

variable "data_volume_gb" {
  description = "Size of the EBS volume holding Postgres data. Separate from the root volume so the instance stays disposable: replace the box, reattach the data."
  type        = number
  default     = 10
}
