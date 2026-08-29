//! Keeps the dashboard, the alert rules and the documentation naming metrics
//! this server emits. A renamed metric blanks its panel and stops its alert
//! firing, and nothing in the build sees it: `promtool` checks that the rules
//! parse, not that the names exist. The emission sites are the registry, and
//! the check is one-directional — an emitted but ungraphed metric is fine.

use std::{collections::BTreeSet, fmt::Write as _, fs, path::Path};

use anyhow::{Context, Result, bail};

use crate::observability::DOCUMENTATION_PATH;
use crate::sources::{no_skip, source_files};

const API_SRC: &str = "crates/api/src";
/// The other thing that emits `ond_*` series: the nightly backup writes its
/// result to node-exporter's textfile collector, so those metrics are born in
/// shell rather than in Rust and are just as real to a rule reading them.
const TEXTFILE_SCRIPT: &str = "infra/box/backup.sh";
const DASHBOARD: &str = "infra/box/grafana/dashboards/ond.json";
const ALERTS: &str = "infra/box/alerts.yml";
const ALERTS_TEST: &str = "infra/box/alerts_test.yml";

/// The macros a metric name can be born in.
const EMITTERS: [&str; 3] = ["counter!", "gauge!", "histogram!"];

/// Suffixes Prometheus appends to a histogram's own series.
///
/// `ond_x` is exposed as `ond_x_bucket`, `ond_x_sum` and `ond_x_count`, and a
/// query names those directly. Stripping them before the lookup stops every
/// quantile on the dashboard reading as an unknown metric.
const HISTOGRAM_SUFFIXES: [&str; 3] = ["_bucket", "_sum", "_count"];

/// Verifies every `ond_*` metric referenced outside the code is emitted inside
/// it.
pub fn check(repo: &Path) -> Result<()> {
    let mut emitted = emitted_metrics(&repo.join(API_SRC))?;
    if emitted.is_empty() {
        bail!("check:metrics: found no metric emissions in {API_SRC} — the scan is broken");
    }

    let textfile_path = repo.join(TEXTFILE_SCRIPT);
    let textfile = fs::read_to_string(&textfile_path)
        .with_context(|| format!("read {} for metric emissions", textfile_path.display()))?;
    let declared = textfile_metrics(&textfile);
    if declared.is_empty() {
        bail!("check:metrics: found no `# TYPE` declarations in {TEXTFILE_SCRIPT}");
    }
    emitted.extend(declared);

    let mut referenced: Vec<(&str, BTreeSet<String>)> = Vec::new();
    for relative in [DASHBOARD, ALERTS, ALERTS_TEST, DOCUMENTATION_PATH] {
        let path = repo.join(relative);
        let source = fs::read_to_string(&path)
            .with_context(|| format!("read {} for metric references", path.display()))?;
        referenced.push((relative, referenced_metrics(&source)));
    }

    validate(&emitted, &referenced)
}

/// The comparison, kept free of the filesystem so its failure case is a unit
/// test rather than a thing to take on trust.
fn validate(emitted: &BTreeSet<String>, referenced: &[(&str, BTreeSet<String>)]) -> Result<()> {
    let unknown: BTreeSet<(&str, &str)> = referenced
        .iter()
        .flat_map(|(file, names)| names.iter().map(move |name| (*file, name.as_str())))
        .filter(|(_, name)| !emitted.contains(resolve(name)))
        .collect();

    if unknown.is_empty() {
        return Ok(());
    }

    let mut report = String::from("check:metrics: these name metrics the API does not emit:\n");
    for (file, name) in &unknown {
        writeln!(report, "  {file}: {name}")?;
    }
    report.push_str("\nEmitted metrics:\n");
    for name in emitted {
        writeln!(report, "  {name}")?;
    }
    bail!(report)
}

/// Every `ond_*` literal passed to a metrics macro anywhere under `crates/api`.
///
/// Text rather than a syntax tree, for the reason `observability::check` gives:
/// the guarded thing is a string literal, and a search finds a literal. A name
/// assembled at runtime escapes this, and escapes a reader too.
fn emitted_metrics(src: &Path) -> Result<BTreeSet<String>> {
    let mut names = BTreeSet::new();

    for path in source_files(src, "rs", &no_skip)? {
        let source = fs::read_to_string(&path)
            .with_context(|| format!("read {} for metric emissions", path.display()))?;
        names.extend(emissions_in(&source));
    }

    Ok(names)
}

/// The `ond_*` names one file emits.
fn emissions_in(source: &str) -> BTreeSet<String> {
    let mut names = BTreeSet::new();

    for (index, _) in source.match_indices("ond_") {
        // Only a name that opens a macro's argument list: walk back through
        // the quote and the parenthesis, trimming between them because rustfmt
        // may put the name on its own line. Without the anchor, a doc comment
        // naming a metric would register as an emission, and the check would
        // validate a dashboard against a series that exists only in prose.
        let before = source[..index].trim_end();
        let Some(before) = before.strip_suffix('"') else {
            continue;
        };
        let Some(before) = before.trim_end().strip_suffix('(') else {
            continue;
        };
        if !EMITTERS
            .iter()
            .any(|macro_name| before.trim_end().ends_with(macro_name))
        {
            continue;
        }

        names.insert(read_name(&source[index..]));
    }

    names
}

/// The `ond_*` names a textfile-collector script declares.
///
/// Read from its `# TYPE` lines, because that line is the declaration in
/// Prometheus' exposition format — what node-exporter parses. The same names
/// also appear in the script's prose and its shell variables.
fn textfile_metrics(source: &str) -> BTreeSet<String> {
    source
        .lines()
        .filter_map(|line| line.trim().strip_prefix("echo '# TYPE "))
        .map(read_name)
        .filter(|name| name.starts_with("ond_"))
        .collect()
}

/// Every `ond_*` token in a file that references metrics.
fn referenced_metrics(source: &str) -> BTreeSet<String> {
    source
        .match_indices("ond_")
        .map(|(index, _)| read_name(&source[index..]))
        .collect()
}

/// Reads a metric name off the front of a slice that begins with `ond_`.
fn read_name(tail: &str) -> String {
    tail.chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect()
}

/// The base name Prometheus would have been given for a series.
fn resolve(name: &str) -> &str {
    for suffix in HISTOGRAM_SUFFIXES {
        if let Some(base) = name.strip_suffix(suffix) {
            return base;
        }
    }
    name
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_histogram_reference_resolves_to_its_declared_name() {
        assert_eq!(
            resolve("ond_grpc_request_duration_seconds_bucket"),
            "ond_grpc_request_duration_seconds"
        );
        assert_eq!(
            resolve("ond_grpc_request_duration_seconds_sum"),
            "ond_grpc_request_duration_seconds"
        );
        assert_eq!(resolve("ond_users_total"), "ond_users_total");
    }

    /// A name stops at the first character a Prometheus name cannot contain,
    /// which is what separates the metric from the label selector after it.
    #[test]
    fn a_name_stops_at_the_selector() {
        assert_eq!(
            read_name(r#"ond_grpc_requests_total{status="0"}"#),
            "ond_grpc_requests_total"
        );
        assert_eq!(read_name("ond_users_total)"), "ond_users_total");
        assert_eq!(read_name("ond_users_total"), "ond_users_total");
    }

    #[test]
    fn only_macro_arguments_count_as_emissions() {
        let emitted = emissions_in(
            r#"
            //! Mentions ond_documented_only in prose, which must not count.
            fn emit() {
                counter!("ond_real_total", "k" => "v").increment(1);
                gauge!("ond_real_gauge").set(1.0);
                histogram!(
                    "ond_real_seconds"
                ).record(1.0);
            }
            "#,
        );

        assert!(emitted.contains("ond_real_total"));
        assert!(emitted.contains("ond_real_gauge"));
        assert!(
            emitted.contains("ond_real_seconds"),
            "a name rustfmt wrapped onto its own line is still an emission"
        );
        assert!(
            !emitted.contains("ond_documented_only"),
            "a metric named only in a comment would let the dashboard reference a series nothing emits"
        );
    }

    /// The check has to fail when a reference goes stale, or it is decoration.
    #[test]
    fn a_reference_to_an_unemitted_metric_is_rejected() {
        let emitted = emissions_in(r#"counter!("ond_real_total").increment(1);"#);

        validate(
            &emitted,
            &[(ALERTS, ["ond_real_total".to_owned()].into_iter().collect())],
        )
        .expect("a reference to an emitted metric resolves");

        let error = validate(
            &emitted,
            &[(
                ALERTS,
                ["ond_renamed_total".to_owned()].into_iter().collect(),
            )],
        )
        .expect_err("a stale reference must fail");

        assert!(error.to_string().contains("ond_renamed_total"));
    }

    /// A histogram is referenced by a series Prometheus derives, never by the
    /// name the code declared, so this is the case most likely to be wrong.
    #[test]
    fn a_quantile_over_a_declared_histogram_resolves() {
        let emitted = emissions_in(r#"histogram!("ond_call_seconds").record(1.0);"#);

        validate(
            &emitted,
            &[(
                DASHBOARD,
                ["ond_call_seconds_bucket".to_owned()].into_iter().collect(),
            )],
        )
        .expect("a bucket series resolves to its declared histogram");
    }
}
