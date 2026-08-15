//! Renders the spoken cues the session player speaks, through `ElevenLabs`, into
//! the clips `OndKit` ships.
//!
//! Nothing about this runs on a phone. The app's spoken vocabulary is a fixed
//! dozen lines per language, so the whole corpus is a few hundred characters
//! per voice — rendered once, when the copy changes, and committed as AAC. That
//! is why a hosted service costs pennies here and why an outage or a deprecated
//! model can never break a build: the audio is in the tree.
//!
//! It replaced a local Kokoro-82M pipeline, which was chosen when size and
//! offline rendering seemed to matter and neither did. Kokoro could not say a
//! word-final /θ/ — "mouth" and "mouse" came back with the same spectrum in
//! three of its four voices — and its only prosody control was a scalar speed,
//! which had to be hand-calibrated per voice because they each read at their
//! own pace.

use std::{collections::BTreeMap, fs, path::Path, path::PathBuf, process::Command};

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};

const API: &str = "https://api.elevenlabs.io/v1";

/// The generic-password item holding the build-time voice credential.
///
/// It reaches no deployment, app bundle, running service, task environment, or
/// process argument. `mise run voice:setup` creates or replaces this item using
/// the Keychain's own hidden interactive prompt.
const KEYCHAIN_SERVICE: &str = "com.ond.voice.elevenlabs";
const KEYCHAIN_ACCOUNT: &str = "api-key";

/// Raw 16-bit PCM at 24 kHz — the rate the cue tones are synthesised at, and
/// the shape the trimming below already expects. Asking for MP3 would mean
/// decoding it again just to measure where the speech starts.
const FORMAT: &str = "pcm_24000";
const SAMPLE_RATE: u32 = 24_000;

/// What every clip is normalised to. A generated set is not level-matched on
/// its own, and a "hold" landing twice as loud as a "breathe out" is the kind
/// of thing that wakes somebody up rather than settling them.
const PEAK: f32 = 0.7;

/// How far below a clip's own peak still counts as speech, for trimming.
const SILENCE_FLOOR: f32 = 0.02;

/// Kept either side of the speech, so a clip does not open on the attack of its
/// first consonant.
///
/// 30ms at 24 kHz. 10ms was not enough: a voice that starts a word loudly
/// crosses the floor within one frame, and "In" came back rising from silence
/// to four-fifths of its peak in 10ms — an onset that had plainly been cut
/// rather than one that was ever spoken.
const EDGE_SAMPLES: usize = 720;

/// What an unfilled voice id looks like in a manifest. Rendering against one
/// would spend a request to be told the voice does not exist, so it is caught
/// here with an instruction instead.
const UNSET: &str = "TODO";

/// One language: the words, and every voice that reads them.
///
/// A manifest is per language rather than per accent because `cues` is a
/// property of the language and `variant` is a property of the voice. Splitting
/// by accent meant the eleven English sentences were written out twice,
/// identically, and the second English table was a place one of them could
/// disagree with itself. French will want its own words; French-Canadian will
/// not.
#[derive(Deserialize)]
struct Manifest {
    /// Named per manifest rather than in code, so trying `eleven_multilingual_v2`
    /// against `eleven_v3` is an edit to a line of TOML and a re-render.
    model: String,
    voices: Vec<Voice>,
    cues: BTreeMap<String, Cue>,
}

#[derive(Deserialize)]
struct Voice {
    /// Ours, and the folder the clips land in — deliberately not the service's
    /// name for the voice. A voice can be swapped for a better one without
    /// moving a file or touching Swift.
    slug: String,
    /// The service's id. `toolkit voice list` prints the ones this account has.
    #[serde(rename = "voice")]
    id: String,
    /// What the picker calls it. Carried through to `voices.json` so the app
    /// reads it as data — swapping a voice does not mean editing an enum.
    title: String,
    /// Which English (or French, or Portuguese) this one speaks, as a BCP-47
    /// tag. Carried through to `voices.json`, where it orders the picker and
    /// will name the language once there is more than one.
    variant: String,
    /// Whether a fresh install breathes to this one. Exactly one voice carries
    /// it, checked at render rather than left to the app to guess — the roster
    /// is data, so which of them is met first is data too.
    #[serde(default)]
    default: bool,
    /// `voice_settings.speed`. 0.7 is the service's floor and the slowest a cue
    /// can be asked for.
    ///
    /// f64 rather than f32 because the service bounds-checks it: 0.7 through an
    /// f32 arrives as 0.699999988079071 and is rejected for being under 0.7.
    speed: f64,
    /// `voice_settings.stability`. High, because a cue is the same sentence
    /// every cycle and the expressive variation this dial buys is variation
    /// nobody breathing to it wants.
    stability: f64,
}

#[derive(Deserialize)]
struct Cue {
    /// The words. Held to `Breath.instruction` by the Swift suite, and what
    /// `voices.json` records — so this is the copy, exactly.
    text: String,
    /// What the service is actually asked to read, where that differs.
    ///
    /// Punctuation is a synthesis hint rather than copy. A bare one-word cue
    /// has no sentence shape to sit in and the model guesses at one: "In" came
    /// back between 0.25s and 2.12s across repeats, while "In." lands inside a
    /// tenth of itself every time. The full stop is a direction to the reader,
    /// so it belongs here and not in the words the app displays.
    say: Option<String>,
}

/// What was actually said, written beside the clips for the Swift suite to
/// check against `Breath.instruction`.
///
/// The one failure that cannot be seen by looking at the tree: a reworded cue
/// leaves the audio saying the old sentence, and nothing about a `.m4a` reveals
/// it. Recording the text turns that into a test needing no service and no key.
#[derive(Serialize)]
struct Rendered {
    variant: String,
    title: String,
    /// Skipped for every voice but the one, so the shipped file says which is
    /// the default once rather than four times over.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    default: bool,
    cues: BTreeMap<String, Spoken>,
}

/// One rendered line: what it says, and how long saying it takes.
///
/// The length is here so the app can decide what fits a phase without opening
/// an audio file. Several of the catalogue's phases are shorter than the
/// sentence describing them, so which cue a phase gets is a rule over numbers —
/// testable on the host with no audio session anywhere near it.
#[derive(Serialize)]
struct Spoken {
    text: String,
    seconds: f32,
}

/// Prints the voices this account can render with, so a manifest can name one.
///
/// The one thing in this workspace that writes to stdout on purpose: putting
/// voice ids in front of somebody editing a manifest is its entire output, and
/// a log line is not that.
#[allow(clippy::print_stdout, reason = "the subcommand's entire purpose")]
pub async fn list() -> Result<()> {
    let key = api_key()?;
    let body: serde_json::Value = reqwest::Client::new()
        .get(format!("{API}/voices"))
        .header("xi-api-key", key)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    let Some(voices) = body["voices"].as_array() else {
        bail!("no voices in the response");
    };
    for voice in voices {
        let labels = voice["labels"]
            .as_object()
            .map(|l| {
                l.values()
                    .filter_map(|v| v.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default();
        println!(
            "{:24}  {:22}  {labels}",
            voice["voice_id"].as_str().unwrap_or("?"),
            voice["name"].as_str().unwrap_or("?"),
        );
    }
    Ok(())
}

/// Reads every manifest under `voice/`, in a stable order.
fn read_manifests(manifest_dir: &Path) -> Result<Vec<(PathBuf, Manifest)>> {
    let mut paths: Vec<PathBuf> = fs::read_dir(manifest_dir)?
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    paths.sort();
    ensure!(
        !paths.is_empty(),
        "no manifests in {}",
        manifest_dir.display()
    );

    paths
        .into_iter()
        .map(|path| {
            let manifest = toml::from_str(&fs::read_to_string(&path)?)
                .with_context(|| format!("parsing {}", path.display()))?;
            Ok((path, manifest))
        })
        .collect()
}

/// Renders every manifest under `voice/` into `out`.
pub async fn render(manifest_dir: &Path, out: &Path) -> Result<()> {
    let key = api_key()?;
    let client = reqwest::Client::new();

    // Every manifest is read and checked before a single request is spent, so a
    // TODO id or a missing default is a first-second failure rather than one
    // found after the fifty-fifth clip has been paid for and written.
    let manifests = read_manifests(manifest_dir)?;
    for (path, manifest) in &manifests {
        for voice in &manifest.voices {
            ensure!(
                voice.id != UNSET,
                "{} has no voice id yet — run `mise run voice:list` and put one in {}",
                voice.slug,
                path.display()
            );
        }
    }
    let defaults: Vec<&str> = manifests
        .iter()
        .flat_map(|(_, m)| &m.voices)
        .filter(|v| v.default)
        .map(|v| v.slug.as_str())
        .collect();
    ensure!(
        defaults.len() == 1,
        "exactly one voice must be the default, found {defaults:?}"
    );

    // Taken away before the first clip is overwritten, and written back only
    // once every one of them has landed. The clips are replaced in place, so a
    // run that dies halfway — a dropped connection, an exhausted quota — would
    // otherwise leave new audio sitting beside the durations of the old, and
    // the fit rule reads those durations to decide what a phase has room for. A
    // missing manifest is loud: the Swift suite fails on an empty roster and
    // the test below fails on unreadable output. A stale one says nothing.
    let ledger = out.join("voices.json");
    if ledger.exists() {
        fs::remove_file(&ledger)?;
    }

    let mut rendered: BTreeMap<String, Rendered> = BTreeMap::new();

    for (_, manifest) in &manifests {
        for voice in &manifest.voices {
            let dir = out.join(&voice.slug);
            fs::create_dir_all(&dir)?;

            let mut said = BTreeMap::new();
            for (cue, line) in &manifest.cues {
                let spoken = line.say.as_deref().unwrap_or(&line.text);
                let samples = speak(&client, &key, &manifest.model, voice, spoken)
                    .await
                    .with_context(|| format!("{} saying \"{}\"", voice.slug, line.text))?;
                encode(&samples, &dir.join(format!("{cue}.m4a")))?;

                #[allow(
                    clippy::cast_precision_loss,
                    reason = "a cue is a few seconds; f32 holds the sample count exactly"
                )]
                let seconds = samples.len() as f32 / SAMPLE_RATE as f32;
                said.insert(
                    cue.clone(),
                    Spoken {
                        text: line.text.clone(),
                        seconds,
                    },
                );
            }

            rendered.insert(
                voice.slug.clone(),
                Rendered {
                    variant: voice.variant.clone(),
                    title: voice.title.clone(),
                    default: voice.default,
                    cues: said,
                },
            );
        }
    }

    prune(out, &rendered)?;

    let json = serde_json::to_string_pretty(&rendered)? + "\n";
    fs::write(&ledger, json)?;
    Ok(())
}

/// Removes everything under `out` that this render did not write — a dropped
/// voice's folder, and a dropped cue's clip inside a folder that stayed.
///
/// The rule is that the tree is exactly what the manifests say, not that it is
/// a superset of them. Pruning folders alone was the superset reading, and it
/// shipped: the mouth cues were dropped from the copy and their audio stayed in
/// two live voices, referenced by nothing, listed nowhere, and copied into the
/// bundle by `Package.swift` along with everything else.
///
/// Called after the renders rather than before them, so a run that dies halfway
/// leaves the previous clips playable instead of an app with no voice.
fn prune(out: &Path, rendered: &BTreeMap<String, Rendered>) -> Result<()> {
    for entry in fs::read_dir(out)? {
        let path = entry?.path();
        if !path.is_dir() {
            continue;
        }
        let Some(voice) = path
            .file_name()
            .and_then(|n| n.to_str())
            .and_then(|slug| rendered.get(slug))
        else {
            fs::remove_dir_all(&path)?;
            continue;
        };

        for clip in fs::read_dir(&path)? {
            let clip = clip?.path();
            let named = clip
                .file_stem()
                .and_then(|n| n.to_str())
                .is_some_and(|stem| voice.cues.contains_key(stem));
            if !named {
                fs::remove_file(&clip)?;
            }
        }
    }
    Ok(())
}

/// Asks the service for one line, and returns it trimmed and level-matched.
async fn speak(
    client: &reqwest::Client,
    key: &str,
    model: &str,
    voice: &Voice,
    text: &str,
) -> Result<Vec<f32>> {
    let response = client
        .post(format!("{API}/text-to-speech/{}", voice.id))
        .header("xi-api-key", key)
        .query(&[("output_format", FORMAT)])
        .json(&serde_json::json!({
            "text": text,
            "model_id": model,
            "voice_settings": { "speed": voice.speed, "stability": voice.stability },
        }))
        .send()
        .await?;

    // The body carries why, and a bare "400 Bad Request" for a wrong voice id
    // or an exhausted quota is a morning lost to guessing which.
    let status = response.status();
    let bytes = response.bytes().await?;
    ensure!(
        status.is_success(),
        "{status}: {}",
        String::from_utf8_lossy(&bytes)
            .chars()
            .take(400)
            .collect::<String>()
    );

    ensure!(
        bytes.len() >= 2,
        "the service returned {} bytes",
        bytes.len()
    );
    let samples: Vec<f32> = bytes
        .chunks_exact(2)
        .map(|pair| f32::from(i16::from_le_bytes([pair[0], pair[1]])) / f32::from(i16::MAX))
        .collect();
    trim(&samples)
}

/// Cuts the padding back to the speech and normalises to `PEAK`.
///
/// Fails rather than returning quiet audio. A bad render is silent, not loud —
/// the failure mode is a clip that writes, encodes and ships without complaint,
/// and is only discovered by somebody breathing to nothing.
fn trim(waveform: &[f32]) -> Result<Vec<f32>> {
    ensure!(
        waveform.iter().all(|s| s.is_finite()),
        "the waveform has samples that are not finite"
    );
    let peak = waveform.iter().fold(0.0_f32, |m, s| m.max(s.abs()));
    ensure!(peak > 1e-4, "the waveform is silent");

    let floor = peak * SILENCE_FLOOR;
    let first = waveform.iter().position(|s| s.abs() > floor).unwrap_or(0);
    let last = waveform
        .iter()
        .rposition(|s| s.abs() > floor)
        .unwrap_or(waveform.len() - 1);
    let from = first.saturating_sub(EDGE_SAMPLES);
    let to = (last + EDGE_SAMPLES).min(waveform.len());

    // Normalised against the whole waveform's peak rather than the trimmed
    // slice's, which are the same number: the sample that set `peak` is louder
    // than a fiftieth of itself, so it is never one of the ones cut away.
    let speech = &waveform[from..to];
    Ok(speech.iter().map(|s| s / peak * PEAK).collect())
}

/// Writes a WAV and hands it to `afconvert` for AAC.
///
/// AAC rather than the WAV the tones beside it are synthesised as, for two
/// reasons WAV cannot answer: `OndKit`'s resources ship to the watch as well,
/// where these are dead weight until it grows a voice of its own; and a
/// regenerated WAV set is half a megabyte of binary churn in every commit that
/// retunes a phrase.
fn encode(samples: &[f32], destination: &Path) -> Result<()> {
    let wav = destination.with_extension("wav");
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(&wav, spec)?;
    for sample in samples {
        // The clamp is what makes the cast total: the product cannot leave
        // i16's range, so there is nothing left for truncation to lose.
        #[allow(
            clippy::cast_possible_truncation,
            reason = "clamped to i16's range above"
        )]
        writer.write_sample((sample.clamp(-1.0, 1.0) * f32::from(i16::MAX)) as i16)?;
    }
    writer.finalize()?;

    let status = Command::new("afconvert")
        .args(["-f", "m4af", "-d", "aac", "-b", "48000", "-s", "3"])
        .arg(&wav)
        .arg(destination)
        .status()
        .context("afconvert — a system tool on macOS, and this task only runs there")?;
    fs::remove_file(&wav)?;
    ensure!(
        status.success(),
        "afconvert failed on {}",
        destination.display()
    );
    Ok(())
}

fn api_key() -> Result<String> {
    let output = Command::new("/usr/bin/security")
        .args([
            "find-generic-password",
            "-s",
            KEYCHAIN_SERVICE,
            "-a",
            KEYCHAIN_ACCOUNT,
            "-w",
        ])
        .output()
        .context("read the ElevenLabs credential from the macOS Keychain")?;

    ensure!(
        output.status.success(),
        "the ElevenLabs credential is absent from the macOS Keychain — run `mise run voice:setup`"
    );

    let key = String::from_utf8(output.stdout)
        .context("the ElevenLabs credential in the macOS Keychain is not UTF-8")?;
    let key = key.trim_end_matches(['\r', '\n']);
    ensure!(
        !key.is_empty(),
        "the ElevenLabs credential in the macOS Keychain is empty — run `mise run voice:setup`"
    );
    Ok(key.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `voices.json` as the app reads it, so a manifest can be checked against
    /// what was actually rendered from it.
    #[derive(Deserialize)]
    struct Recorded {
        variant: String,
        title: String,
        cues: BTreeMap<String, RecordedCue>,
    }

    #[derive(Deserialize)]
    struct RecordedCue {
        text: String,
    }

    fn voice_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("voice")
    }

    fn manifests() -> Vec<Manifest> {
        let mut paths: Vec<PathBuf> = fs::read_dir(voice_dir())
            .expect("the voice manifests are committed beside this crate")
            .filter_map(|entry| entry.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|e| e == "toml"))
            .collect();
        paths.sort();
        assert!(!paths.is_empty(), "no manifests to render from");

        paths
            .iter()
            .map(|path| {
                let text = fs::read_to_string(path).expect("a committed manifest is readable");
                toml::from_str(&text).unwrap_or_else(|e| panic!("parsing {}: {e}", path.display()))
            })
            .collect()
    }

    fn clips_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../ios/Packages/OndCore/Sources/OndKit/Resources/Voice")
    }

    fn recorded() -> BTreeMap<String, Recorded> {
        let text =
            fs::read_to_string(clips_dir().join("voices.json")).expect("the render is committed");
        serde_json::from_str(&text).expect("voices.json is the shape the render writes")
    }

    /// Every manifest parses and is renderable — checked before a run spends 55
    /// metered requests to discover a typo in the fifty-fifth.
    #[test]
    fn a_manifest_is_ready_to_render() {
        let mut slugs = Vec::new();

        for manifest in manifests() {
            assert!(!manifest.cues.is_empty(), "a language with nothing to say");
            for (name, cue) in &manifest.cues {
                assert!(!cue.text.trim().is_empty(), "{name} says nothing");
            }

            for voice in &manifest.voices {
                assert_ne!(voice.id, UNSET, "{} has no voice id yet", voice.slug);
                assert!(
                    !voice.variant.trim().is_empty(),
                    "{} has no variant",
                    voice.slug
                );
                // The service rejects anything under 0.7, and it does so on the
                // request rather than on the manifest.
                assert!(
                    (0.7..=1.2).contains(&voice.speed),
                    "{} asks for speed {}, which the service will refuse",
                    voice.slug,
                    voice.speed
                );
                slugs.push(voice.slug.clone());
            }
        }

        let mut unique = slugs.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(
            unique.len(),
            slugs.len(),
            "two voices share a folder: {slugs:?}"
        );
    }

    /// The clips beside the app were rendered from the manifests as they stand.
    ///
    /// The render is manual, key-gated and macOS-only, so the likely mistake is
    /// rewording a cue and not re-running it — and audio that says the old
    /// sentence looks exactly like audio that says the new one. The Swift suite
    /// catches the same drift from the other side; this catches it here, where
    /// the edit was made, without a key or a network.
    #[test]
    fn the_committed_clips_say_what_the_manifests_say() {
        let recorded = recorded();

        for manifest in manifests() {
            for voice in &manifest.voices {
                let Some(clip) = recorded.get(&voice.slug) else {
                    panic!("{} is in a manifest but was never rendered", voice.slug);
                };
                assert_eq!(clip.variant, voice.variant, "{} moved language", voice.slug);
                assert_eq!(clip.title, voice.title, "{} was renamed", voice.slug);

                for (name, cue) in &manifest.cues {
                    let Some(said) = clip.cues.get(name) else {
                        panic!(
                            "{} has no clip for {name} — re-run `mise run generate:voice`",
                            voice.slug
                        );
                    };
                    assert_eq!(
                        &said.text, &cue.text,
                        "{}/{name} was reworded but never re-rendered",
                        voice.slug
                    );
                }
            }
        }
    }

    /// Nothing ships that `voices.json` does not name.
    ///
    /// The other direction from the test above, and the one nothing was
    /// watching: a cue dropped from a manifest left its audio behind in every
    /// voice that kept its folder, and an orphaned clip is invisible from every
    /// angle — it plays, it says a real sentence, and no code path reaches it.
    /// `Package.swift` copies the folder wholesale, so it shipped.
    #[test]
    fn nothing_ships_that_the_manifests_do_not_name() {
        let recorded = recorded();

        for entry in fs::read_dir(clips_dir()).expect("the clips are committed") {
            let path = entry.expect("a readable directory entry").path();
            if !path.is_dir() {
                continue;
            }
            let slug = path
                .file_name()
                .and_then(|n| n.to_str())
                .expect("a clip folder is named after a voice")
                .to_owned();
            let Some(voice) = recorded.get(&slug) else {
                panic!("{slug} has clips but is in no manifest — re-run the render");
            };

            for clip in fs::read_dir(&path).expect("a readable voice folder") {
                let clip = clip.expect("a readable clip").path();
                let stem = clip
                    .file_stem()
                    .and_then(|n| n.to_str())
                    .expect("a clip is named after its cue");
                assert!(
                    voice.cues.contains_key(stem),
                    "{slug}/{stem} is a cue nothing says any more — re-run the render"
                );
            }
        }
    }
}
