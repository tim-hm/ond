//! Renders the spoken cues the session player speaks, through `ElevenLabs`, into
//! the clips `OndKit` ships.
//!
//! Nothing about this runs on a phone. The app's spoken vocabulary is eleven
//! fixed lines per accent, so the whole corpus is a few hundred characters per
//! voice — rendered once, when the copy changes, and committed as AAC. That is
//! why a hosted service costs pennies here and why an outage or a deprecated
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

/// Read at the point of use and never anywhere else. A build-time credential:
/// it reaches no deployment, no app bundle and no running service, so the two
/// variables the backend is allowed are still two.
const KEY_VAR: &str = "ELEVENLABS_API_KEY";

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

#[derive(Deserialize)]
struct Manifest {
    variant: String,
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
    /// `voice_settings.speed`. 0.7 is the service's floor and the slowest a cue
    /// can be asked for.
    ///
    /// f64 rather than f32 because the service bounds-checks it: 0.7 through an
    /// f32 arrives as 0.699999988079071 and is rejected for being under 0.7.
    #[serde(default)]
    speed: Option<f64>,
    /// `voice_settings.stability`. High, because a cue is the same sentence
    /// every cycle and the expressive variation this dial buys is variation
    /// nobody breathing to it wants.
    #[serde(default)]
    stability: Option<f64>,
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
    #[serde(default)]
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

/// Renders every manifest under `voice/` into `out`.
pub async fn render(manifest_dir: &Path, out: &Path) -> Result<()> {
    let key = api_key()?;
    let client = reqwest::Client::new();

    let mut manifests: Vec<PathBuf> = fs::read_dir(manifest_dir)?
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    manifests.sort();
    ensure!(
        !manifests.is_empty(),
        "no manifests in {}",
        manifest_dir.display()
    );

    let mut rendered: BTreeMap<String, Rendered> = BTreeMap::new();

    for path in manifests {
        let manifest: Manifest = toml::from_str(&fs::read_to_string(&path)?)
            .with_context(|| format!("parsing {}", path.display()))?;

        for voice in &manifest.voices {
            ensure!(
                voice.id != UNSET,
                "{} has no voice id yet — run `mise run voice:list` and put one in {}",
                voice.slug,
                path.display()
            );

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
                    variant: manifest.variant.clone(),
                    title: voice.title.clone(),
                    cues: said,
                },
            );
        }
    }

    // After the renders rather than before them, so a run that dies halfway
    // leaves the previous clips playable instead of an app with no voice.
    for entry in fs::read_dir(out)? {
        let path = entry?.path();
        let stale = path.is_dir()
            && path
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| !rendered.contains_key(n));
        if stale {
            fs::remove_dir_all(&path)?;
        }
    }

    let json = serde_json::to_string_pretty(&rendered)? + "\n";
    fs::write(out.join("voices.json"), json)?;
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
    let mut settings = serde_json::Map::new();
    if let Some(speed) = voice.speed {
        settings.insert("speed".into(), serde_json::json!(speed));
    }
    if let Some(stability) = voice.stability {
        settings.insert("stability".into(), serde_json::json!(stability));
    }

    let response = client
        .post(format!("{API}/text-to-speech/{}", voice.id))
        .header("xi-api-key", key)
        .query(&[("output_format", FORMAT)])
        .json(&serde_json::json!({
            "text": text,
            "model_id": model,
            "voice_settings": settings,
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

    let speech = &waveform[from..to];
    let loudest = speech.iter().fold(0.0_f32, |m, s| m.max(s.abs()));
    Ok(speech.iter().map(|s| s / loudest * PEAK).collect())
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
    std::env::var(KEY_VAR)
        .with_context(|| format!("{KEY_VAR} is not set — an ElevenLabs key renders the cues"))
}
