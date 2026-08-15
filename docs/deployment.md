# Deployment

One Graviton EC2 instance running the API, Postgres, and Caddy under Docker Compose, provisioned by OpenTofu from `infra/`, deployed by `mise run deploy`. Nothing in this document runs automatically: provisioning and deploying are deliberate operator actions, and none of the `check`/CI machinery touches AWS.

## Shape

```text
infra/            OpenTofu root module — the AWS resources
infra/bootstrap/  applied once, before everything — the state bucket and the IAM user
infra/box/        what runs on the instance — compose.yaml + Caddyfile, rsynced by deploy
infra/cloud-init.yaml   first-boot setup — the tailnet, Docker, the data volume, the backup cron
Dockerfile        one image, both workspace binaries (api + migrate)
web/              the marketing one-pager, rsynced beside infra/box and served by Caddy
```

The public hostname is **`ondbreathe.app`**, named twice on purpose: as the Route53 zone in `infra/main.tf` and as the site block in `infra/box/Caddyfile`. Nothing renders the Caddyfile — deploy rsyncs it as-is — so those two literals are kept in step by hand, and both files say so.

DNS is applied from `infra/`, not edited at the registrar: the hosted zone and the apex `A` record land with the address they point at, so a record aimed at a released IP is not a state this repo can reach. The registrar holds one thing, the NS delegation, set once from the `name_servers` output.

The zone also carries the domain's mail, which no part of this deployment serves — the box runs no mail server. Five values across four record sets hand it to Google Workspace, where the name is enrolled as a secondary domain of a Workspace registered under a different one — the two apex `TXT` strings share one set, which is why they cannot be separate resources:

| Record                         | What it does                                                                  |
| :----------------------------- | :---------------------------------------------------------------------------- |
| apex `TXT` `google-site-…`     | Proves control of the zone. Re-checked, so deleting it un-verifies the domain |
| apex `TXT` `v=spf1 …`          | Names Google as the only sender. At `~all`, so other senders are marked       |
| apex `MX` `1 smtp.google.com.` | Delivery. One host, not the five `ASPMX` records older guides give            |
| `google._domainkey` `TXT`      | DKIM public key, split across two strings — see the comment on the resource   |
| `_dmarc` `TXT` `p=none`        | Makes the two above enforceable. Reports only, and no `rua` yet               |

**Those five values belong to one Workspace tenant.** Applying `infra/` into a fresh AWS account publishes another tenant's verification token and DKIM key, which verifies nothing and signs nothing. A second deployment replaces all five from its own Workspace admin console, or drops them if it serves no mail.

The instance is disposable; the things worth keeping live elsewhere:

- **Postgres data** — on a separate EBS volume (`ond-data` label, mounted at `/srv/data`), so replacing the instance replaces no data. The database password lives on that volume too (`/srv/data/ond.env`), because Postgres keeps its own hash inside the cluster files — a fresh instance regenerating it would strand the data.
- **Backups** — nightly `pg_dump | gzip | aws s3 cp` from a cron installed by cloud-init, into the `backup_bucket` output, 30-day expiry. Credentials come from the instance profile; no keys exist on the box.
- **TLS certificates** — in the `caddy-data` Docker volume, persisted so redeploys never touch ACME rate limits.

The public entrance is Caddy on 443 (80 redirects and answers ACME challenges), reverse-proxying to the API on 18100. gRPC-Web is plain HTTP POST underneath, so no special proxy handling is needed. Postgres is not reachable from outside the compose network at all.

## Reachability

Two ports answer on the public address, and neither is 22. The way to a shell is the tailnet.

The box joins it from cloud-init — the pinned Tailscale package from its Noble apt repository, then `tailscale up` with the key passed in as `tailscale_auth_key` — and registers as **`ond-api`**, which is the `ssh_host` output and so what `mise run deploy` dials. Cloud-init verifies the repository key against the SHA-256 committed beside the package version and holds that package after installation; upgrading Tailscale is therefore a deliberate edit to `infra/cloud-init.yaml`, followed by rebuilding the instance. The connection arrives over `tailscale0` rather than the ENI, which is where a security group's rules apply and the far end of a WireGuard tunnel is not.

`--ssh` is what answers it, and it replaces rather than supplements the usual arrangement. Tailscale SSH claims port 22 on the tailnet address, so a session no `ssh` rule in the policy file matches is refused outright — it is not handed down to sshd. sshd still listens, but after the cutover nothing can reach it: intercepted on the tailnet address, closed on the public one. **The tailnet ACL is therefore a deploy dependency**, and this is the rule the box needs:

```json
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["tag:server"],
    "users":  ["ubuntu"],
  },
],
```

`accept` and not `check`, which is the opposite of what an interactive admin tailnet should choose. `check` demands a periodic browser sign-in, and `deploy` opens several sessions back to back with nobody watching — `docker save | ssh`, two rsyncs, then the compose commands — which is the pattern Tailscale's own documentation warns that check mode disrupts.

`ssh_public_key` survives this without authorising anything, and stays because the key pair is ForceNew on the instance: dropping it would rebuild the box to remove a credential that already opens nothing.

Two properties of the auth key are load-bearing rather than stylistic, and `infra/variables.tf` says so on the variable:

- **Single-use.** It reaches the box in `user_data`, which anything running on the box can read back through IMDS, and which stays readable for the life of the instance. A key already spent by the time cloud-init finishes is worth nothing to whoever reads it. The cost is that the key in `terraform.tfvars` is spent the moment a box uses it — replacing the instance means minting a new one first, because a rebuild with a stale key is a box that boots and never appears.
- **Tagged `tag:server`.** A node registered under a person's identity inherits that person's key expiry and drops off the tailnet some months later, silently, with nothing failing until the next deploy. Tagged nodes do not expire.

### When the tailnet is what broke

`user_data` describes how the _next_ box joins; it does nothing to a running one, whose cloud-init finished long ago. Changing `tailscale_auth_key` and applying is an in-place update that the instance never reads. So the standing repair for a box that is not on the tailnet — a join that failed at first boot, an expired node, a fresh key — is Session Manager, which needs no port, no key, and nothing on the tailnet to be working:

```sh
# Needs the session-manager-plugin installed locally; the instance side is the
# SSM role attached in infra/main.tf.
aws ssm start-session --target <instance-id> --profile ond
sudo tailscale up --auth-key='<a fresh single-use key>' --hostname=ond-api --accept-dns=false --ssh
```

Those flags have to match the ones in `infra/cloud-init.yaml`, which nothing reconciles — a box repaired with different flags behaves differently from the box its own rebuild would produce. `tailscale status` on the box and `ssh ubuntu@ond-api` from the laptop are what say it took.

### The dashboard

Grafana answers at **`https://<the box's MagicDNS name>:18104/`** and at no other address. The container publishes 3000 on loopback; `tailscale serve` is the whole route in, and Tailscale issues the certificate for the node's own name, so the dashboard is HTTPS without Caddy or ACME being involved. What it shows and why those numbers is in [observability.md](observability.md).

**18104 rather than 443, and this took the site down once.** `tailscale serve` defaults to 443 and binds it on the tailnet address; Docker publishes Caddy on `0.0.0.0:443`, which includes that address. Both cannot hold it. What that looks like is worth recognising, because nothing about it says "port conflict": Caddy loses the bind and ends up **running with no network attached**, so `docker ps` says up, `docker compose config` says it is on `ond_default`, `docker inspect` shows no networks at all, and the public site answers nothing while Prometheus reports every container healthy. The repair is to free 443 (`tailscale serve --https=443 off`) and recreate Caddy.

Two things have to be switched on in the tailnet, once each, and both fail in the same readable way — `tailscale serve` says so and names the link:

- **Serve**, at `https://login.tailscale.com/f/serve?node=<node>`. Enabling it also provisions the HTTPS certificates it needs.
- The **`ssh` policy rule** covering `tag:server`, which [Reachability](#reachability) already required for `mise run deploy`.

A box that joined the tailnet but cannot serve is the ordinary partial failure here: SSH works, the dashboard 404s, and `sudo tailscale serve status` on the box says `No serve config`. Re-running `tailscale serve --bg --https=18104 3000` is the repair, and it is idempotent — but never without the `--https` flag, for the reason above.

## The site

`web/` is three pages — `index.html`, `privacy.html`, `support.html` — one stylesheet, and the two App Store badge SVGs, no build step and no bundler. The badges are Apple's own artwork, committed rather than hotlinked so the page makes no external request. `mise run deploy` rsyncs the directory to `/srv/ond/web/`, which `infra/box/compose.yaml` mounts read-only into Caddy. The two document pages are reached without their extension (`/privacy`, `/support`), which the `try_files` directive in the Caddyfile is what makes work — the app ships those URLs as literals.

`infra/box/Caddyfile` splits the hostname by path rather than running a second one, so there is one A record and one certificate. The API side is enumerated (`/ond.v1.*`, `/health`, `/about`) and the site is the fallback, never the other way round: matching the proto package prefix covers every service the contract will ever grow, so a static file can never shadow an RPC.

The one-pager's technique glyphs are the reference for the apps' own drawings, with nothing checking the two agree — see [code-structure.md](code-structure.md) before editing them.

## Environment

The container gets exactly the two variables `crates/api/src/config.rs` reads, and no more — anything else belongs in config.rs as a derivation, per CLAUDE.md §1.4.

| Variable       | Required | Where it comes from                                                              |
| :------------- | :------- | :------------------------------------------------------------------------------- |
| `OND_ENV`      | yes      | Literal `production` in `infra/box/compose.yaml` — JSON logs, no permissive CORS |
| `DATABASE_URL` | yes      | Assembled in the same file from the generated `POSTGRES_PASSWORD`                |

**The assistant has no variable, and that is the design.** It calls Amazon Bedrock directly, signing each call with the `ond-api` instance profile that `infra/main.tf` attaches — reachable from inside the container because `http_put_response_hop_limit` is 2, the same reason the backup cron's `aws s3 cp` works. So there is no key on the box, nothing to add after a rebuild, and nothing to rotate. Where the box cannot sign for Bedrock at all — a laptop with no AWS identity, a CI runner — the API boots normally and the assistant answers from its rule-based fallback; every RPC still returns a real answer, flagged so the client can say so.

The two things that _are_ configuration live in code and in OpenTofu: which model, in `BEDROCK_MODEL_ID`; and which regions its inference profile may route to, in `assistant_profile_regions`. See [the assistant's permission](#the-assistants-permission) below.

## The assistant's permission

`aws_iam_role_policy.invoke_model` in `infra/main.tf` is what lets the box call the coach's model. It grants `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` — the streaming one is not optional, because the chat RPC streams — over two ARN families, and both are required:

- the **inference profile**, `arn:aws:bedrock:eu-west-2:<account>:inference-profile/eu.anthropic.…`, which is where the call is addressed; and
- the **underlying foundation model** in every region that profile may forward to, `arn:aws:bedrock:<destination>::foundation-model/anthropic.…`.

A policy granting only the first is the failure worth knowing about. It is valid, it plans, it applies — and then every call comes back `AccessDenied`, on the box, because an invocation is authorised against both. The foundation-model id is derived from the profile id rather than written twice, so those two cannot drift.

**Whether it actually works is `/about`'s `assistant` field**, and reading it is the check to make after any change to this policy:

| Value         | What it means                                                                                              |
| :------------ | :--------------------------------------------------------------------------------------------------------- |
| `live`        | Bedrock has answered in this process — the coach's replies are coming from the model                       |
| `untried`     | A model is installed and calls will be attempted, but none has succeeded yet. Nothing is proven either way |
| `interrupted` | The model is installed but its breaker is open: recent calls failed, and the rules answer for the cooldown |
| `fallback`    | This process could not sign for a model at boot, and will answer from the rules until it is restarted      |

**Every one of those is derived from what calls did, never from what is configured**, and that rule is the whole design rather than an implementation detail. A field that read `bedrock` because `config.rs` names Bedrock would be this outage wearing a new hat: the configuration was correct the entire time, and the IAM grant behind it was missing.

So `live` is evidence and the other three are not. Credentials that resolve are not credentials that are _authorised_: with no `invoke_model` grant the instance profile still signed, so the API installed a Bedrock client and would have called itself live for as long as nobody asked it anything — and nobody could, because a chat request needs önd+. In code the rule is that `GuardedModelClient` is the only thing that can produce `live`, on a call that actually returned; every other implementation defaults to `untried` and cannot promote itself.

So the reading to expect on a fresh deploy is `untried`, and it turns `live` the first time a Coach-tier request is answered — which is that same request being _shown_ to have come from Bedrock, by `curl`, with no log on the box. `fallback` in production is the other failure worth knowing, and it means the box could not sign at all.

The destination list is `assistant_profile_regions`, and it has **no default on purpose**. It is read from the inference profile's detail page in the Bedrock console, and a guessed list fails only when Bedrock happens to route to the region that was left out — so a plan that stops for a missing value is where that mistake belongs. The same list is what `web/privacy.html` asserts about where coach requests are processed, which is the other reason not to infer it. It lives in `infra/terraform.tfvars` beside `ssh_public_key` and `tailscale_auth_key`:

```hcl
assistant_profile_regions = ["eu-west-1", "eu-central-1", ...]  # from the console
```

Changing the model means changing `BEDROCK_MODEL_ID` in `crates/api/src/config.rs` and `assistant_inference_profile` here together, then re-reading the destination list — a different profile can have a different one. That constant's doc comment carries the standing constraint on which models may be adopted at all.

## Identity and state

Three AWS profiles, and the split is the point:

| Profile   | Who                                           | May run                                                    |
| :-------- | :-------------------------------------------- | :--------------------------------------------------------- |
| `holmie`  | the account root                              | `infra:bootstrap:*`, once, and nothing else                |
| `ond`     | the `ond-tofu` IAM user                       | everything: `infra:plan`, `infra:apply`, `deploy`          |
| `ond-dev` | the `ond-dev` role, assumed by that same user | `dev` and `assistant:smoke` — invoke Bedrock, nothing else |

The mise tasks pin `AWS_PROFILE` themselves, so none is something to remember or export. `ond-dev` exists because `mise run dev` idles all day holding whatever credential it was given, and before the role that credential was AdministratorAccess; its stanza is in docs/contributing.md, and it holds no keys — the `ond` credential is the one set on the laptop.

State lives in the S3 bucket `infra/bootstrap` creates — versioned, encrypted, private, TLS-only, and `prevent_destroy`. Locking is OpenTofu's S3-native `use_lockfile`; the DynamoDB table older Terraform documentation calls for does not exist and is not needed.

The bucket is `ond-tfstate-136339248297` and the user is `ond-tofu` — both renamed from `breathe-*` after the app became önd, so nothing in the account still answers to the old name. The bucket name is written in two places that nothing reconciles: `state_bucket` in `infra/bootstrap/variables.tf`, which creates it, and the `backend "s3"` block in `infra/versions.tf`, which reads it.

Renaming it again is four steps, and the first is the one that is not obvious. `bucket` is ForceNew, so changing it plans a destroy-and-recreate — which `prevent_destroy` on that resource refuses outright, failing the whole plan before anything is created. The guard is right and stays; bootstrap has to be told to forget the old bucket instead of being asked to replace it:

```sh
# 1. Bootstrap forgets the old bucket. It stays alive, unmanaged, holding state.
tofu -chdir=infra/bootstrap state rm \
  aws_s3_bucket.tfstate aws_s3_bucket_policy.tfstate \
  aws_s3_bucket_public_access_block.tfstate \
  aws_s3_bucket_server_side_encryption_configuration.tfstate \
  aws_s3_bucket_versioning.tfstate
# 2. Create the new one, with the new name already in variables.tf.
mise run infra:bootstrap:apply
# 3. Carry state across, having edited the backend literal in infra/versions.tf.
AWS_PROFILE=ond tofu -chdir=infra init -migrate-state
# 4. Only once `mise run infra:plan` is a clean no-op: empty and delete the old
#    bucket by hand. It is versioned, so every version must go before the bucket.
```

Editing the backend literal on its own — without step 2 having created the bucket it names — points the backend at nothing and strands every resource.

`infra/bootstrap` keeps **local** state, because it builds the bucket the other root stores state in. Losing that file is not an incident: it manages one bucket and one IAM user, both named, both re-importable in two commands.

## Bootstrap (once per AWS account)

1. `mise run infra:bootstrap:init`, then `mise run infra:bootstrap:apply` — creates the state bucket and the `ond-tofu` IAM user. This is the only step that runs as the account root.
2. Mint the user's credential. Tofu deliberately does not, because the provider would write the secret into a state file in plaintext:

   ```sh
   aws iam create-access-key --user-name ond-tofu --profile holmie
   ```

3. Put it in `~/.aws/credentials` under `[ond]`, with a matching `[profile ond]` (`region = eu-west-2`) in `~/.aws/config`.
4. Delete the **root** access key in the IAM console. Root keys cannot be scoped, and an audit cannot tell one use of them from another — replacing them is the entire reason step 1 exists.

## First launch (deliberate, in order)

1. Bootstrap, above.
2. Create `infra/terraform.tfvars` (gitignored) with the required variables: `ssh_public_key`, `tailscale_auth_key`, and `assistant_profile_regions`. None has a default — `tofu plan` prompts for a missing one and fails outright under `-input=false` — and `infra/variables.tf` says on each why a committed default would be the wrong thing. Mint the auth key single-use and tagged `tag:server`; see [Reachability](#reachability) for what each of those buys.
3. `mise run infra:init` — downloads providers and modules, and reaches the S3 backend.
4. `mise run infra:plan` — read the plan — then `mise run infra:apply`. The apply creates the `ond-dev` role; add its `[profile ond-dev]` stanza to `~/.aws/config` now (docs/contributing.md shows it), or `mise run dev` answers from the rule-based fallback until you do.
5. Delegate the domain: set the four addresses from the `name_servers` output as `ondbreathe.app`'s nameservers at the registrar, then wait until `dig +short ondbreathe.app` answers with the `elastic_ip`. Do this before the first deploy — Caddy requests its certificate on first boot, and issuance fails (then retries with backoff) until the name resolves. The `A` record itself was applied in step 4; delegation is what makes the world able to read it.
6. `mise run deploy` — builds the arm64 image locally, ships it over SSH (`docker save | docker load`, no registry), rsyncs `infra/box/`, runs `migrate` as a one-shot container, brings the stack up. From a machine on the tailnet: the SSH it uses goes to `ond-api`, which resolves nowhere else. If it does not resolve, the box has not joined — [Reachability](#when-the-tailnet-is-what-broke), not this step.
7. `curl https://ondbreathe.app/health` → `{"status":"ok"}`, and `/about` for the commit now serving and the assistant's resolved mode.

Every subsequent release is step 6 alone.

## The two halves of a release

A release is a module and a container, and only one of them is `deploy`'s job. Nothing used to connect the two, so an infrastructure change could merge, deploy, pass every check and be believed live while the `tofu apply` that would have applied it was a command somebody had to remember. `aws_iam_role_policy.invoke_model` sat unapplied that way for a day, and the coach answered every request from its rule-based fallback.

`mise run infra:drift` is what connects them. It runs `tofu plan -detailed-exitcode` — read-only, so it is safe on `deploy`'s critical path — and fails when the plan is not empty. `deploy` depends on it, which means the box cannot be shipped to while the module describing it is pending.

A plan rather than a checksum over `infra/`, because "the repository changed" is the wrong question: a resource deleted in the console drifts without a commit touching anything, and a reformatted file is not drift at all. Only the provider knows.

It fails rather than warns, on the same reasoning as `DEPLOY_DRIFT_ACK` and with the same shape of escape hatch: `INFRA_DRIFT_ACK="<why>"` proceeds anyway, for the hotfix where unrelated pending infrastructure should not be what stops a fix reaching a broken production. A warning printed before a five-minute image build is a warning nobody reads, which is the failure being fixed rather than a new one.

Run it on its own whenever the question is "is production what this repository says".

## The advisory check

`deploy` also runs `mise run check:audit` — `cargo audit` against the RustSec database — before it builds anything, and refuses to ship when an advisory matches `Cargo.lock`.

It sits here rather than in `mise run check` because it is the one check whose answer is not a function of this tree: it changes when somebody else publishes an advisory, so in the gate it would eventually fail a commit that touched nothing related, and what that teaches is to skip the gate. It also needs the network, which the gate deliberately does not. `.github/workflows/audit.yml` would have run it nightly, but Actions are disabled for this repository, so the watch existed and could not fire. A deploy is the one recurring, network-connected moment this project reliably has.

It is also the moment the answer matters most. The App Store signature check and the Sign in with Apple identity-token check are hand-rolled over `ring` and `x509-parser`; an advisory against those crates decides who gets entitled and who gets signed in. `DEPLOY_ADVISORY_ACK="<why>"` proceeds anyway, on the same reasoning as the other two hatches — an advisory in a crate unrelated to an outage should not be what stops the fix.

## Restore

```sh
aws s3 cp s3://<backup_bucket>/ond-<date>.sql.gz - | gunzip |
  ssh ubuntu@ond-api 'docker compose -f /srv/ond/compose.yaml exec -T db psql -U postgres ond'
```

Restores into the live database; for a from-scratch rebuild, apply migrations first (`deploy` does) and restore over the empty schema.

## Decisions and their edges

- **Postgres in Docker, not RDS.** At V1 scale RDS buys nothing a dump schedule doesn't, and costs more than the instance itself. The graduation path is a `DATABASE_URL` change and one restore — take it when backups stop being an acceptable recovery story, not before.
- **No registry.** `docker save | ssh docker load` is the whole supply chain while there is one box. A registry earns its place when there are two, or when CI deploys.
- **S3 state, no DynamoDB.** OpenTofu locks against S3 itself (`use_lockfile`), so the lock table every Terraform tutorial provisions is dead weight. `infra/bootstrap` keeps local state only because it creates the bucket.
- **An IAM user, not SSO, and not least privilege.** One account and one operator do not justify standing up Identity Center. `AdministratorAccess` because this user's only job is applying a module that creates IAM roles, buckets, EC2 and EBS — scoping it would mean enumerating every service the module might ever grow into, and the enumeration would be stale immediately. The security this buys is not a smaller blast radius; it is a credential that can be rotated and revoked, which a root key cannot.
- **Provenance via build arg.** `.dockerignore` excludes `.git`, so `build.rs` cannot read the commit inside a container. `deploy` passes it as `GIT_COMMIT_HASH`, and `build.rs` prefers that over git — otherwise `/about` reports `"unknown"` in the one environment where the question matters.
- **The reported commit is `origin/main`, and the tree has to match it.** Deploys run from the `gitbutler/workspace` branch, whose `HEAD` is a synthetic commit on no branch — a hash nobody can look up, which is worthless as an answer to "what is on the box". So `deploy` reports `origin/main` and refuses to build when the working tree differs from it, listing what drifted. `DEPLOY_DRIFT_ACK="<why>"` overrides that for a hotfix that cannot wait for a PR; the acknowledged build reports `<hash>-dirty`, so the shortcut stays visible in `/about` long after the incident.
- **A tailnet, not a narrowed CIDR and not a bastion.** 22/tcp used to be open to `admin_cidr`, which is a residential prefix: it is re-issued by the ISP, it covers every other subscriber on it, and it strands the operator on the day it renews. A bastion is a second box to patch and a second key to lose. The tailnet is neither — nothing is exposed, the credential is a device rather than an address, and the same enrolment is what makes an internal dashboard reachable without ever publishing it. What it costs is a dependency on a third party being up between the laptop and the box, which is why the SSM path stays.
- **The box self-heals but is not monitored.** `restart: unless-stopped` covers crashes; nothing yet pages anyone. Real monitoring is tracked as launch work rather than built here.
