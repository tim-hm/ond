//! Prints the seeded technique catalogue as JSON, for the apps to ship and the
//! drawings to derive from.
//!
//! A second binary rather than a subcommand on `migrate`: the catalogue is a
//! `const` in `seed.rs`, so this needs no database, no environment, and no async
//! runtime — and the migration binary is the one every deploy runs, which is not
//! where an argv matcher for a development-time export belongs.
//!
//! Run through `mise run generate:catalogue`, which redirects it into the
//! committed `ios/Packages/OndCore/Sources/OndKit/Resources/catalogue.json`
//! that `mise run check:generated` pins — a resource of `OndKit`, so a device
//! that has never reached the server still holds every technique.

use anyhow::Result;

// The one place in the workspace that may write to stdout: this is the
// binary's output, not a log line.
#[allow(clippy::print_stdout, reason = "the export is this binary's output")]
fn main() -> Result<()> {
    print!("{}", migrate::seed::catalogue_json()?);
    Ok(())
}
