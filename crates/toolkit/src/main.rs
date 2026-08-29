//! Repo tooling that is too much for a mise task and has no business being a
//! loose script.
//!
//! Subcommands take no flags: every path they need is a fact about this
//! repository rather than a choice.

use std::path::PathBuf;

use anyhow::{Result, bail};

mod box_config;
mod comments;
mod deploy;
mod deps;
mod dev;
mod devices;
mod git;
mod icons;
mod ios;
mod metrics;
mod migrations;
mod observability;
mod proto;
mod screenshots;
mod sources;
mod system_test;
mod voice;

#[tokio::main]
async fn main() -> Result<()> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = root.join("../..").canonicalize()?;
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["voice"] => {
            voice::render(
                &root.join("voice"),
                &repo.join("ios/Packages/OndCore/Sources/OndKit/Resources/Voice"),
            )
            .await
        }
        ["voice", "list"] => voice::list().await,
        ["icons"] => icons::render(&repo),
        ["box", "check", name] => box_config::check(&repo, name),
        ["deploy", "api"] => deploy::api(&repo),
        ["deploy", "website"] => deploy::website(&repo),
        ["infra", "drift"] => deploy::drift(&repo),
        ["proto", "check"] => proto::check(&repo),
        ["deps", "check"] => deps::check(&repo),
        ["dev", "plus"] => dev::plus(None).await,
        ["dev", "plus", user] => dev::plus(Some(user)).await,
        ["dev", "sign-in"] => dev::sign_in(None).await,
        ["dev", "sign-in", user] => dev::sign_in(Some(user)).await,
        ["ios", "sim", "phone"] => ios::sim_phone(&repo),
        ["ios", "sim", "watch"] => ios::sim_watch(&repo),
        ["ios", "device", "phone"] => ios::device_phone(&repo),
        ["ios", "device", "watch"] => ios::device_watch(&repo),
        ["ios", "ui-test"] => ios::ui_test(&repo),
        ["ios", "screenshots"] => screenshots::capture(&repo),
        ["test", "system"] => system_test::run(&repo).await,
        ["comments", "check"] => comments::length::check(&repo),
        ["comments", "baseline"] => comments::length::write_baseline(&repo),
        ["migrations", "check"] => migrations::check(&repo),
        ["observability", "check"] => observability::check(&repo),
        ["metrics", "check"] => metrics::check(&repo),
        other => bail!(
            "usage: toolkit <voice [list] | icons | box check <config> | comments <check | baseline> | deploy <api | website> | dev <plus | sign-in> [user] | infra drift | proto check | deps check | ios <sim | device> <phone | watch> | ios <ui-test | screenshots> | test system | migrations check | observability check | metrics check> (got {other:?})"
        ),
    }
}
