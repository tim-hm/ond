//! Prints the seeded reference data as JSON: techniques, foundations, and the
//! routing over them. Its source is constant data in `seed/catalogue.rs`, so it
//! needs no database and no runtime, which is why it is a separate binary from
//! the one every deploy runs. `mise run generate:catalogue` redirects it into
//! the committed `OndKit` resource `catalogue.json`, which `check:generated` pins.

use anyhow::Result;

// The one place in the workspace that may write to stdout: this is the
// binary's output, not a log line.
#[allow(clippy::print_stdout, reason = "the export is this binary's output")]
fn main() -> Result<()> {
    print!("{}", migrate::seed::catalogue_json()?);
    Ok(())
}
