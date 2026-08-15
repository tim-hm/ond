//! Keeps the dashboard, the alert rules and the documentation naming metrics
//! this server actually emits.
//!
//! The failure this prevents is silent in both directions and always has been.
//! Rename a metric in Rust and the panel that read it goes blank, which looks
//! like "nothing is happening" rather than like a bug — and any alert on it
//! stops being able to fire at all, which looks like health. Nothing in the
//! build sees either: the dashboard is JSON, the rules are YAML, and `promtool`
//! checks that they parse, not that the names in them exist.
//!
//! So the emission sites are the registry. Every `ond_*` name reachable from a
//! `counter!`, `gauge!` or `histogram!` in `crates/api` is what may be
//! referenced; anything else named in a query is a typo or a leftover.
//!
//! Deliberately one-directional. A metric emitted and graphed nowhere is fine —
//! plenty exist to be queried by hand during an incident — so this asserts that
//! every reference resolves, never that every metric is referenced.

use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write as _,
    fs,
    path::Path,
};

use anyhow::{Context, Result, bail};

const API_SRC: &str = "crates/api/src";
/// The other thing that emits `ond_*` series: the nightly backup writes its
/// result to node-exporter's textfile collector, so those metrics are born in
/// shell rather than in Rust and are just as real to a rule reading them.
const TEXTFILE_SCRIPT: &str = "infra/box/backup.sh";
const DASHBOARD: &str = "infra/box/grafana/dashboards/ond.json";
const ALERTS: &str = "infra/box/alerts.yml";
const ALERTS_TEST: &str = "infra/box/alerts_test.yml";
const DOCUMENTATION: &str = "docs/observability.md";

/// The macros a metric name can be born in.
const EMITTERS: [&str; 3] = ["counter!", "gauge!", "histogram!"];

/// Suffixes Prometheus appends to a histogram's own series.
///
/// A histogram declared as `ond_x` is exposed as `ond_x_bucket`, `ond_x_sum`
/// and `ond_x_count`, and a query has to name those directly —
/// `histogram_quantile` takes the buckets. Stripping them before the lookup is
/// what stops every quantile on the dashboard reading as an unknown metric.
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
    for relative in [DASHBOARD, ALERTS, ALERTS_TEST, DOCUMENTATION] {
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
    let mut unknown: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for (file, names) in referenced {
        for name in names {
            if !emitted.contains(resolve(name)) {
                unknown.entry(file).or_default().insert(name);
            }
        }
    }

    if unknown.is_empty() {
        return Ok(());
    }

    let mut report = String::from("check:metrics: these name metrics the API does not emit:\n");
    for (file, names) in &unknown {
        for name in names {
            writeln!(report, "  {file}: {name}")?;
        }
    }
    report.push_str("\nEmitted metrics:\n");
    for name in emitted {
        writeln!(report, "  {name}")?;
    }
    bail!(report)
}

/// Every `ond_*` literal passed to a metrics macro anywhere under `crates/api`.
///
/// Text rather than a syntax tree, on the same reasoning `observability::check`
/// gives for the Swift side: the thing being guarded is a string literal, and a
/// literal is exactly what a search finds. A name assembled at runtime would
/// escape this — and would also escape a reader, which is the better argument
/// for not writing one.
fn emitted_metrics(src: &Path) -> Result<BTreeSet<String>> {
    let mut names = BTreeSet::new();

    for path in rust_files(src)? {
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
        // Only a name that opens a macro's argument list — walking backwards
        // through the opening quote and then the macro's own parenthesis, with
        // a trim between them because rustfmt is free to put the name on its
        // own line, and every labelled emission in `obs::metrics` is written
        // that way. Without the anchor, prose in a doc comment naming a metric
        // would register as an emission, and this check would then happily
        // validate a dashboard against a series that exists only in a comment.
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
/// Read from its `# TYPE` lines rather than from every mention, because that
/// line *is* the declaration in Prometheus' exposition format — it is what
/// node-exporter parses — while the same names also appear in the script's
/// prose and its shell variables. Anchoring on the declaration keeps this as
/// strict as the Rust side, where only a macro argument counts.
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

fn rust_files(dir: &Path) -> Result<Vec<std::path::PathBuf>> {
    let mut files = Vec::new();
    let mut stack = vec![dir.to_path_buf()];

    while let Some(current) = stack.pop() {
        for entry in fs::read_dir(&current)
            .with_context(|| format!("read directory {}", current.display()))?
        {
            let path = entry?.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|extension| extension == "rs") {
                files.push(path);
            }
        }
    }

    Ok(files)
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
