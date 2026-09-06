use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, ensure};
use base64::Engine;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use reqwest::Method;
use ring::rand::SystemRandom;
use ring::signature::{ECDSA_P256_SHA256_FIXED_SIGNING, EcdsaKeyPair};
use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
struct Change {
    method: MethodName,
    path: String,
    body: Value,
}

#[derive(Deserialize)]
#[serde(rename_all = "UPPERCASE")]
enum MethodName {
    Post,
    Patch,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ChangeSet {
    One(Change),
    Many(Vec<Change>),
}

pub async fn read(path: &str) -> Result<()> {
    request(Method::GET, path, None).await
}

pub async fn apply(file: &Path) -> Result<()> {
    let changes = match serde_json::from_slice(&std::fs::read(file)?)? {
        ChangeSet::One(change) => vec![change],
        ChangeSet::Many(changes) => changes,
    };
    for change in &changes {
        validate(change)?;
    }
    for change in changes {
        request(method(&change), &change.path, Some(change.body)).await?;
    }
    Ok(())
}

fn method(change: &Change) -> Method {
    match change.method {
        MethodName::Post => Method::POST,
        MethodName::Patch => Method::PATCH,
    }
}

fn validate(change: &Change) -> Result<()> {
    let method = method(change);
    ensure!(
        (method == Method::POST && change.path == "/v1/subscriptionPrices")
            || (method == Method::PATCH
                && [
                    "/v1/subscriptionLocalizations/",
                    "/v1/appStoreVersionLocalizations/"
                ]
                .iter()
                .any(|prefix| change.path.starts_with(prefix))),
        "Only subscription prices and listing text can be changed by this task"
    );
    Ok(())
}

#[allow(
    clippy::print_stdout,
    reason = "the command returns the API response for review"
)]
async fn request(method: Method, path: &str, body: Option<Value>) -> Result<()> {
    ensure!(
        path.starts_with("/v1/"),
        "Use an App Store Connect /v1/ path"
    );
    let client = reqwest::Client::builder()
        .timeout(Duration::from_mins(1))
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let mut request = client
        .request(
            method,
            format!("https://api.appstoreconnect.apple.com{path}"),
        )
        .bearer_auth(token()?);
    if let Some(body) = body {
        request = request.json(&body);
    }
    let response = request.send().await?;
    let status = response.status();
    let body = response.text().await?;
    ensure!(status.is_success(), "App Store Connect {status}: {body}");
    println!("{body}");
    Ok(())
}

fn token() -> Result<String> {
    let key_id = std::env::var("OND_ASC_KEY_ID").context("Set OND_ASC_KEY_ID in .env")?;
    let issuer = std::env::var("OND_ASC_ISSUER_ID").context("Set OND_ASC_ISSUER_ID in .env")?;
    let home = std::env::var("HOME")?;
    let pem = std::fs::read_to_string(format!(
        "{home}/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"
    ))
    .context("Read the App Store Connect private key")?;
    let encoded: String = pem
        .lines()
        .filter(|line| !line.starts_with("---"))
        .collect();
    let bytes = STANDARD.decode(encoded)?;
    let random = SystemRandom::new();
    let key = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &bytes, &random)
        .map_err(|_| anyhow::anyhow!("Invalid App Store Connect signing key"))?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let header = json!({"alg": "ES256", "kid": key_id, "typ": "JWT"});
    let claims = json!({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"});
    let input = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&header)?),
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims)?)
    );
    let signature = key
        .sign(&random, input.as_bytes())
        .map_err(|_| anyhow::anyhow!("Could not sign the App Store Connect request"))?;
    Ok(format!("{input}.{}", URL_SAFE_NO_PAD.encode(signature)))
}
