//! Renders the spoken cues the session player speaks, from committed phonemes
//! through Kokoro to the clips `OndKit` ships.
//!
//! The model is not on the device and never will be: the app's whole spoken
//! vocabulary is eleven fixed lines per accent, so it is cheaper by every
//! measure to say them once here and commit the audio than to carry 300 MB of
//! weights, an inference runtime and a GPLv3 phonemiser into a phone. What
//! ships is a folder of AAC.

use std::{collections::BTreeMap, fs, path::Path, path::PathBuf, process::Command};

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};

/// Where the weights, the tokeniser and the voice packs are fetched from.
const REPO: &str = "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main";

/// fp32 rather than either quantisation. `model_fp16.onnx` returns NaN on short
/// inputs — 11 of 100 cue renders across four voices and five speeds came back
/// with no signal at all — and a silent clip is a defect that looks like
/// success. `model_q8f16.onnx` measured clean too and is a quarter the size,
/// but nothing about this task is size-constrained: it runs on a laptop when
/// the copy changes and writes files somebody then listens to.
const MODEL: &str = "onnx/model.onnx";

/// Kokoro emits at 24 kHz, mono. Resampling would only lose something.
const SAMPLE_RATE: u32 = 24_000;

/// The amplitude every clip is normalised to. Kokoro's own output ranges from
/// 0.43 to 0.99 peak across the cue set — better than two to one — so without
/// this a session's "hold" lands twice as loud as its "breathe out".
const PEAK: f32 = 0.7;

/// How far below a clip's own peak still counts as speech, for trimming.
/// Kokoro pads its output with close to a second of near-silence, which would
/// otherwise be a second of a phase spent waiting for the voice to start.
const SILENCE_FLOOR: f32 = 0.02;

/// Kept either side of the speech after trimming, so a clip does not open on
/// the attack of its first consonant.
const EDGE_SAMPLES: usize = 240;

/// A voice pack is 510 style vectors, one per token count, of 256 floats each.
const STYLE_DIM: usize = 256;

#[derive(Deserialize)]
struct Manifest {
    variant: String,
    voices: Vec<Voice>,
    cues: BTreeMap<String, Cue>,
}

#[derive(Deserialize)]
struct Voice {
    id: String,
    title: String,
    /// Calibrated per voice so every voice speaks at the same pace — see the
    /// comment on `[[voices]]` in the manifests.
    speed: f32,
}

#[derive(Deserialize)]
struct Cue {
    text: String,
    phonemes: String,
}

/// What was actually said, written beside the clips for the Swift suite to
/// check against `Breath.instruction`.
///
/// The one thing that cannot be caught by looking at the tree: a reworded cue
/// leaves the audio saying the old sentence, and nothing about a `.m4a` reveals
/// that. Recording the text here turns it into a test that needs neither the
/// model nor the runtime.
#[derive(Serialize)]
struct Rendered {
    variant: String,
    title: String,
    speed: f32,
    cues: BTreeMap<String, Spoken>,
}

/// One rendered line: what it says, and how long saying it takes.
///
/// The length is here so the app can decide what fits a phase without opening
/// an audio file to find out. Three of the catalogue's phases are shorter than
/// the sentence that describes them — bellows breath runs a second each way —
/// and which cue a phase gets is then a rule over numbers, testable on the host
/// with no audio session anywhere near it.
#[derive(Serialize)]
struct Spoken {
    text: String,
    seconds: f32,
}

/// Renders every manifest under `voice/` into `out`.
pub async fn render(manifest_dir: &Path, out: &Path, cache: &Path) -> Result<()> {
    fs::create_dir_all(cache)?;
    let model = fetch(cache, MODEL, "model.onnx").await?;
    let vocab = load_vocab(&fetch(cache, "tokenizer.json", "tokenizer.json").await?)?;

    let mut session = ort::session::Session::builder()?
        .commit_from_file(&model)
        .with_context(|| format!("loading {}", model.display()))?;

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
            let pack = fetch(
                cache,
                &format!("voices/{}.bin", voice.id),
                &format!("{}.bin", voice.id),
            )
            .await?;
            let styles = load_styles(&pack)?;
            let dir = out.join(&voice.id);
            fs::create_dir_all(&dir)?;

            let mut said = BTreeMap::new();
            for (key, cue) in &manifest.cues {
                let samples = speak(&mut session, &vocab, &styles, &cue.phonemes, voice.speed)
                    .with_context(|| format!("{} saying \"{}\"", voice.id, cue.text))?;
                encode(&samples, &dir.join(format!("{key}.m4a")))?;
                #[allow(
                    clippy::cast_precision_loss,
                    reason = "a cue is a few seconds; f32 holds the sample count exactly"
                )]
                let seconds = samples.len() as f32 / SAMPLE_RATE as f32;
                said.insert(
                    key.clone(),
                    Spoken {
                        text: cue.text.clone(),
                        seconds,
                    },
                );
            }

            rendered.insert(
                voice.id.clone(),
                Rendered {
                    variant: manifest.variant.clone(),
                    title: voice.title.clone(),
                    speed: voice.speed,
                    cues: said,
                },
            );
        }
    }

    let json = serde_json::to_string_pretty(&rendered)? + "\n";
    fs::write(out.join("voices.json"), json)?;
    Ok(())
}

/// Runs one line through the model and returns it trimmed and level-matched.
fn speak(
    session: &mut ort::session::Session,
    vocab: &BTreeMap<char, i64>,
    styles: &[f32],
    phonemes: &str,
    speed: f32,
) -> Result<Vec<f32>> {
    let mut ids = Vec::with_capacity(phonemes.chars().count() + 2);
    ids.push(0);
    for character in phonemes.chars() {
        let id = vocab
            .get(&character)
            .with_context(|| format!("no token for {character:?} — not in Kokoro's phoneme set"))?;
        ids.push(*id);
    }
    ids.push(0);

    // The style vector is indexed by how many tokens are being spoken, without
    // the boundary pair — a longer line is read with a different delivery.
    let index = ids.len() - 2;
    let offset = index * STYLE_DIM;
    let style = styles
        .get(offset..offset + STYLE_DIM)
        .with_context(|| format!("line of {index} tokens is longer than the voice pack"))?;

    let outputs = session.run(ort::inputs![
        "input_ids" => ort::value::Tensor::from_array(([1, ids.len()], ids.clone()))?,
        "style" => ort::value::Tensor::from_array(([1, STYLE_DIM], style.to_vec()))?,
        "speed" => ort::value::Tensor::from_array(([1], vec![speed]))?,
    ])?;
    let (_, waveform) = outputs["waveform"].try_extract_tensor::<f32>()?;

    trim(waveform)
}

/// Cuts the model's padding back to the speech and normalises to `PEAK`.
///
/// Fails rather than returning quiet audio. A bad render here is silent, not
/// loud — the failure mode is a clip that writes, encodes and ships without
/// complaint, and is only discovered by somebody breathing to nothing.
fn trim(waveform: &[f32]) -> Result<Vec<f32>> {
    ensure!(
        waveform.iter().all(|s| s.is_finite()),
        "the model returned a waveform with no finite samples in it"
    );
    let peak = waveform.iter().fold(0.0_f32, |m, s| m.max(s.abs()));
    ensure!(peak > 1e-4, "the model returned silence");

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

/// Kokoro's tokeniser is a flat phoneme-to-id map — no merges, no subwords.
fn load_vocab(path: &Path) -> Result<BTreeMap<char, i64>> {
    let json: serde_json::Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    let Some(entries) = json["model"]["vocab"].as_object() else {
        bail!("{} has no model.vocab object", path.display());
    };
    entries
        .iter()
        .map(|(token, id)| {
            let mut characters = token.chars();
            let (Some(character), None) = (characters.next(), characters.next()) else {
                bail!("token {token:?} is not a single character");
            };
            let id = id
                .as_i64()
                .with_context(|| format!("token {token:?} has no integer id"))?;
            Ok((character, id))
        })
        .collect()
}

fn load_styles(path: &Path) -> Result<Vec<f32>> {
    let bytes = fs::read(path)?;
    ensure!(
        bytes.len() % (STYLE_DIM * 4) == 0,
        "{} is not a whole number of {STYLE_DIM}-float style vectors",
        path.display()
    );
    Ok(bytes
        .chunks_exact(4)
        .map(|word| f32::from_le_bytes([word[0], word[1], word[2], word[3]]))
        .collect())
}

/// Downloads `remote` into the cache once, and returns where it landed.
///
/// The weights are 310 MB and the repo has no business holding them: they are
/// an input to a task that runs when the copy changes, not an artefact of it.
async fn fetch(cache: &Path, remote: &str, local: &str) -> Result<PathBuf> {
    let path = cache.join(local);
    if path.exists() {
        return Ok(path);
    }
    let url = format!("{REPO}/{remote}");
    let bytes = reqwest::get(&url)
        .await
        .with_context(|| format!("fetching {url}"))?
        .error_for_status()?
        .bytes()
        .await?;
    // Through a temporary file, so an interrupted download is not mistaken for
    // a complete one by the `exists` check above on the next run.
    let partial = path.with_extension("partial");
    fs::write(&partial, &bytes)?;
    fs::rename(&partial, &path)?;
    Ok(path)
}
