//! Rasters of the committed vectors, for the places an SVG cannot go.
//! `favicon.ico` and `apple-touch-icon.png` serve browsers and iOS home
//! screens. A watchOS submission needs an `appiconset` PNG, which the Icon
//! Composer bundle cannot supply — see `ios/project.yml`. `mise run generate`
//! rewrites all three, so a source change and its rasters land in one commit.

use std::{fs, io, path::Path};

use anyhow::{Context, Result, bail};
use resvg::{
    tiny_skia::{Pixmap, PixmapPaint, Transform},
    usvg::{Options, Tree},
};

/// The sizes `favicon.ico` carries.
///
/// A browser picks the nearest and scales, so the set is the three it actually
/// asks for: 16 in a tab, 32 on a retina tab and in a bookmark list, 48 in
/// Windows' own surfaces. 64 and up are what the SVG is for.
const ICO_SIZES: [u32; 3] = [16, 32, 48];

/// The edge of `apple-touch-icon.png`, in points times two.
///
/// 180 is the size iOS asks for on every retina phone and the one it downsamples
/// from everywhere else. A single file, because the alternative is six that all
/// say the same thing.
const TOUCH_SIZE: u32 = 180;

/// The app icon's light layers, bottom to top.
///
/// Not `web/favicon.svg`: that file is its own drawing — a closed ring over a
/// glow, with no ground — so a home screen would show a mark the App Store
/// listing does not. Light, because iOS applies its own appearance here.
const TOUCH_LAYERS: [&str; 2] = ["GroundLight.svg", "RingLight.svg"];

/// The watch app icon's dark layers, bottom to top.
///
/// The dark set, because the wrist has one appearance and it is this one: the
/// system draws every icon over an always-black screen, which is the same
/// reasoning that keeps the watch entry of every colorset on the dark value.
const WATCH_LAYERS: [&str; 2] = ["GroundDark.svg", "RingDark.svg"];

/// The edge App Store Connect requires of the watch `appiconset` image.
const WATCH_SIZE: u32 = 1024;

/// Renders the two site fallback icons into `web/`, and the watch app icon
/// into its catalogue.
pub fn render(repo: &Path) -> Result<()> {
    let web = repo.join("web");

    write_favicon(&web)?;
    write_touch_icon(repo, &web)?;
    write_watch_icon(repo)?;

    Ok(())
}

/// Rasterises `favicon.svg` into the multi-size `favicon.ico` beside it.
///
/// The light variant lands, because `usvg` has no media query support: it reads
/// the presentation attributes and never applies the dark override. An ICO
/// cannot carry two appearances anyway, and the drawing has no ground.
fn write_favicon(web: &Path) -> Result<()> {
    let source = web.join("favicon.svg");
    let svg = fs::read(&source).with_context(|| format!("reading {}", source.display()))?;
    let tree = parse(&svg, &source)?;

    let mut icon = ico::IconDir::new(ico::ResourceType::Icon);
    for size in ICO_SIZES {
        let pixmap = rasterise(&tree, size)?;
        let image = ico::IconImage::from_rgba_data(size, size, pixmap.data().to_vec());
        icon.add_entry(ico::IconDirEntry::encode(&image).context("encoding an ICO entry")?);
    }

    let destination = web.join("favicon.ico");
    let mut file = fs::File::create(&destination)
        .with_context(|| format!("creating {}", destination.display()))?;
    icon.write(&mut file)
        .with_context(|| format!("writing {}", destination.display()))?;

    Ok(())
}

/// Composes the app icon's light layers into `apple-touch-icon.png`.
///
/// The icon has no single source file: `icon.json` is a layer list Xcode
/// composites, and the layers are the only place the drawing exists. Painting
/// them in order is what that file describes.
fn write_touch_icon(repo: &Path, web: &Path) -> Result<()> {
    let assets = repo.join("ios/Ond/AppIcon.icon/Assets");
    let mut canvas =
        Pixmap::new(TOUCH_SIZE, TOUCH_SIZE).context("allocating the touch icon canvas")?;

    for layer in TOUCH_LAYERS {
        let source = assets.join(layer);
        let svg = fs::read(&source).with_context(|| format!("reading {}", source.display()))?;
        let tree = parse(&svg, &source)?;
        let rendered = rasterise(&tree, TOUCH_SIZE)?;

        canvas.draw_pixmap(
            0,
            0,
            rendered.as_ref(),
            &PixmapPaint::default(),
            Transform::identity(),
            None,
        );
    }

    let destination = web.join("apple-touch-icon.png");
    canvas
        .save_png(&destination)
        .with_context(|| format!("writing {}", destination.display()))?;

    Ok(())
}

/// Composes the dark layers into the watch catalogue's `AppIcon-1024.png`.
///
/// Through the `png` crate, not `Pixmap::save_png`: App Store validation
/// rejects an app icon with an alpha channel, and tiny-skia only writes RGBA.
/// The composite is opaque, so dropping every fourth byte discards nothing.
fn write_watch_icon(repo: &Path) -> Result<()> {
    let assets = repo.join("ios/Ond/AppIcon.icon/Assets");
    let mut canvas =
        Pixmap::new(WATCH_SIZE, WATCH_SIZE).context("allocating the watch icon canvas")?;

    for layer in WATCH_LAYERS {
        let source = assets.join(layer);
        let svg = fs::read(&source).with_context(|| format!("reading {}", source.display()))?;
        let tree = parse(&svg, &source)?;
        let rendered = rasterise(&tree, WATCH_SIZE)?;

        canvas.draw_pixmap(
            0,
            0,
            rendered.as_ref(),
            &PixmapPaint::default(),
            Transform::identity(),
            None,
        );
    }

    let rgb: Vec<u8> = canvas
        .data()
        .chunks_exact(4)
        .flat_map(|pixel| [pixel[0], pixel[1], pixel[2]])
        .collect();

    let destination = repo.join("ios/OndWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png");
    let file = fs::File::create(&destination)
        .with_context(|| format!("creating {}", destination.display()))?;
    let mut encoder = png::Encoder::new(io::BufWriter::new(file), WATCH_SIZE, WATCH_SIZE);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    encoder
        .write_header()
        .and_then(|mut writer| writer.write_image_data(&rgb))
        .with_context(|| format!("writing {}", destination.display()))?;

    Ok(())
}

/// Parses one SVG, naming the file when it will not.
fn parse(svg: &[u8], source: &Path) -> Result<Tree> {
    Tree::from_data(svg, &Options::default())
        .with_context(|| format!("parsing {}", source.display()))
}

/// Draws a parsed tree into a square pixmap of `size`.
///
/// Every source here is a 1024 square, so one scale factor serves both axes. A
/// source that stops being square would distort silently, which is what the
/// check below refuses rather than reports at a tab.
fn rasterise(tree: &Tree, size: u32) -> Result<Pixmap> {
    let source = tree.size();
    if (source.width() - source.height()).abs() > f32::EPSILON {
        bail!(
            "expected a square source, got {}x{}",
            source.width(),
            source.height()
        );
    }

    let mut pixmap = Pixmap::new(size, size).context("allocating a pixmap")?;
    #[expect(
        clippy::cast_precision_loss,
        reason = "every size here is under 256, well inside f32's exact integers"
    )]
    let scale = size as f32 / source.width();

    resvg::render(
        tree,
        Transform::from_scale(scale, scale),
        &mut pixmap.as_mut(),
    );

    Ok(pixmap)
}
