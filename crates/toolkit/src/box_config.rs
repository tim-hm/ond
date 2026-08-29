//! One substitution table for the box's config templates.
//!
//! `deploy:api` renders `infra/box/*.tmpl` with real values; the `check:*`
//! tasks render the same templates with stand-ins. Sharing the table keeps
//! the two from disagreeing about a template's holes.

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail, ensure};

pub struct Placeholder {
    pub name: &'static str,
    stand_in: &'static str,
}

struct Template {
    source: &'static str,
    rendered: &'static str,
    placeholders: &'static [Placeholder],
}

const REGION: Placeholder = Placeholder {
    name: "__REGION__",
    stand_in: "eu-west-2",
};

const TEMPLATES: &[Template] = &[
    Template {
        source: "infra/box/alertmanager.yml.tmpl",
        rendered: "infra/box/alertmanager.yml",
        placeholders: &[
            REGION,
            Placeholder {
                name: "__ALARM_TOPIC_ARN__",
                stand_in: "arn:aws:sns:eu-west-2:000000000000:check",
            },
        ],
    },
    Template {
        source: "infra/box/cron.d/ond.tmpl",
        rendered: "infra/box/cron.d/ond",
        placeholders: &[
            REGION,
            Placeholder {
                name: "__BACKUP_BUCKET__",
                stand_in: "ond-backup-check",
            },
            Placeholder {
                name: "__HEARTBEAT_NAMESPACE__",
                stand_in: "OndCheck",
            },
            Placeholder {
                name: "__HEARTBEAT_METRIC__",
                stand_in: "Heartbeat",
            },
        ],
    },
    Template {
        source: "infra/box/loki.yaml.tmpl",
        rendered: "infra/box/loki.yaml",
        placeholders: &[
            REGION,
            Placeholder {
                name: "__LOGS_BUCKET__",
                stand_in: "ond-logs-check",
            },
        ],
    },
    Template {
        source: "infra/box/Caddyfile.tmpl",
        rendered: "infra/box/Caddyfile",
        placeholders: &[
            Placeholder {
                name: "__API_HOST__",
                stand_in: "api.check.invalid",
            },
            Placeholder {
                name: "__WEB_HOST__",
                stand_in: "check.invalid",
            },
        ],
    },
];

/// The validator images, pinned to the tags `infra/box/compose.yaml` runs so
/// the parser doing the checking is the parser the box boots with. A unit
/// test holds the two files together.
const PROMETHEUS: &str = "prom/prometheus:v3.7.3";
const ALERTMANAGER: &str = "prom/alertmanager:v0.33.0";
const LOKI: &str = "grafana/loki:3.7.2";
const CADDY: &str = "caddy:2";
const ALLOY: &str = "grafana/alloy:v1.15.0";

/// Render every template into its committed-beside path with real values.
///
/// `lookup` maps a placeholder name (`__REGION__`) to its value; an absent or
/// empty value fails by name, because an empty substitution deletes the
/// placeholder and the survivors check below cannot see it.
pub fn render(repo: &Path, lookup: &dyn Fn(&str) -> Option<String>) -> Result<()> {
    for template in TEMPLATES {
        let mut text = read(repo, template.source)?;
        for placeholder in template.placeholders {
            let value = lookup(placeholder.name)
                .filter(|value| !value.is_empty())
                .with_context(|| {
                    format!(
                        "{} is empty — refusing to render {} around it",
                        placeholder.name, template.source
                    )
                })?;
            text = text.replace(placeholder.name, &value);
        }
        reject_survivors(template.source, &text)?;
        std::fs::write(repo.join(template.rendered), text)
            .with_context(|| format!("write {}", template.rendered))?;
    }
    Ok(())
}

/// Validate one of the box's configs the way its own container parses it.
pub fn check(repo: &Path, name: &str) -> Result<()> {
    match name {
        "alerts" => docker(
            repo,
            &[
                ("infra/box", "/box"),
                // promtool's test file names alerts.yml relative to itself,
                // so the directory is mounted rather than the one file.
            ],
            PROMETHEUS,
            Some("sh"),
            &[
                "-c",
                "promtool check rules /box/alerts.yml && promtool test rules /box/alerts_test.yml",
            ],
        ),
        "alertmanager" => {
            let rendered = stand_in(repo, "infra/box/alertmanager.yml.tmpl", "alertmanager.yml")?;
            docker(
                repo,
                &[(&rendered, "/alertmanager.yml")],
                ALERTMANAGER,
                Some("amtool"),
                &["check-config", "/alertmanager.yml"],
            )
        }
        "loki" => {
            let rendered = stand_in(repo, "infra/box/loki.yaml.tmpl", "loki.yaml")?;
            docker(
                repo,
                &[(&rendered, "/loki.yaml")],
                LOKI,
                None,
                &["-config.file=/loki.yaml", "-verify-config"],
            )
        }
        "caddy" => {
            let rendered = stand_in(repo, "infra/box/Caddyfile.tmpl", "Caddyfile")?;
            docker(
                repo,
                &[(&rendered, "/etc/caddy/Caddyfile")],
                CADDY,
                None,
                &[
                    "caddy",
                    "validate",
                    "--config",
                    "/etc/caddy/Caddyfile",
                    "--adapter",
                    "caddyfile",
                ],
            )
        }
        "alloy" => docker(
            repo,
            &[("infra/box/alloy.river", "/config.alloy")],
            ALLOY,
            None,
            &["validate", "/config.alloy"],
        ),
        other => bail!("box check: unknown config {other:?}"),
    }
}

/// Render `source` with the table's stand-in values into `target/box-check/`,
/// returning the rendered path relative to the repository.
fn stand_in(repo: &Path, source: &str, file_name: &str) -> Result<String> {
    let template = TEMPLATES
        .iter()
        .find(|template| template.source == source)
        .with_context(|| format!("{source} is not in the template table"))?;
    let mut text = read(repo, source)?;
    for placeholder in template.placeholders {
        text = text.replace(placeholder.name, placeholder.stand_in);
    }
    reject_survivors(source, &text)?;

    let directory = repo.join("target/box-check");
    std::fs::create_dir_all(&directory).context("create target/box-check")?;
    std::fs::write(directory.join(file_name), text)
        .with_context(|| format!("write target/box-check/{file_name}"))?;
    Ok(format!("target/box-check/{file_name}"))
}

/// A surviving placeholder means the template has a hole the table does not
/// fill; amtool and friends would accept it as an ordinary string, so the
/// deploy would be the first thing to notice.
fn reject_survivors(source: &str, text: &str) -> Result<()> {
    if let Some(survivor) = survivor(text) {
        bail!("{source}: {survivor} survived rendering — add it to the table in box_config.rs");
    }
    Ok(())
}

fn survivor(text: &str) -> Option<&str> {
    let bytes = text.as_bytes();
    let mut index = 0;
    while let Some(offset) = text[index..].find("__") {
        let start = index + offset;
        let mut end = start + 2;
        while end < bytes.len() && (bytes[end].is_ascii_uppercase() || bytes[end] == b'_') {
            end += 1;
        }
        if text[start + 2..end].ends_with("__") && end - start > 4 {
            return Some(&text[start..end]);
        }
        index = start + 2;
    }
    None
}

fn read(repo: &Path, path: &str) -> Result<String> {
    std::fs::read_to_string(repo.join(path)).with_context(|| format!("read {path}"))
}

/// Run a validator container. Mounts are `(repo-relative source, container
/// path)`, all read-only.
fn docker(
    repo: &Path,
    mounts: &[(&str, &str)],
    image: &str,
    entrypoint: Option<&str>,
    args: &[&str],
) -> Result<()> {
    let mut command = Command::new("docker");
    command.args(["run", "--rm"]);
    for (source, target) in mounts {
        let source = repo
            .join(source)
            .canonicalize()
            .with_context(|| format!("resolve {source} — run the render before validating it"))?;
        command.arg("-v");
        command.arg(format!("{}:{target}:ro", source.display()));
    }
    if let Some(entrypoint) = entrypoint {
        command.args(["--entrypoint", entrypoint]);
    }
    command.arg(image);
    command.args(args);

    let status = command
        .status()
        .with_context(|| format!("run {image} — is Docker running?"))?;
    ensure!(status.success(), "{image} rejected the config");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    /// Every hole in every template is in the table, and the table names no
    /// hole a template lacks — the drift this module exists to prevent.
    #[test]
    fn the_table_covers_every_template_placeholder() {
        for template in TEMPLATES {
            let text = read(&repo(), template.source).unwrap();
            for placeholder in template.placeholders {
                assert!(
                    text.contains(placeholder.name),
                    "{}: the table lists {} but the template has no such hole",
                    template.source,
                    placeholder.name
                );
            }
            let mut rendered = text;
            for placeholder in template.placeholders {
                rendered = rendered.replace(placeholder.name, placeholder.stand_in);
            }
            assert_eq!(
                survivor(&rendered),
                None,
                "{}: a placeholder the table does not fill",
                template.source
            );
        }
    }

    /// The validator tags must be the tags the box runs, or a config can
    /// validate here and fail to parse there.
    #[test]
    fn validator_images_match_the_box_compose_file() {
        let compose = read(&repo(), "infra/box/compose.yaml").unwrap();
        for image in [PROMETHEUS, ALERTMANAGER, LOKI, CADDY, ALLOY] {
            assert!(
                compose.contains(&format!("image: {image}")),
                "{image} is not the tag infra/box/compose.yaml runs"
            );
        }
    }

    #[test]
    fn an_empty_value_is_rejected_by_name() {
        let error = render(&repo(), &|_| Some(String::new()))
            .expect_err("an empty value must fail")
            .to_string();
        assert!(error.contains("__REGION__"), "{error}");
    }

    #[test]
    fn a_surviving_placeholder_is_found() {
        assert_eq!(survivor("host: __API_HOST__\n"), Some("__API_HOST__"));
        assert_eq!(survivor("a __dunder__ python name"), None);
        assert_eq!(survivor("____"), None);
        assert_eq!(survivor("no holes"), None);
    }
}
