import OndKit
import OndUI
import SwiftUI

struct TechniqueSources: View {
    let technique: Technique

    private struct Source {
        let title: String
        let scope: String
        let address: String
    }

    var body: some View {
        DisclosureGroup("Research sources") {
            VStack(alignment: .leading, spacing: Theme.Spacing.standard) {
                Text(
                    "Selected research behind this explanation. Study results may not apply to adjusted timings or to everyone."
                )
                .font(.callout)
                .foregroundStyle(Theme.Ink.secondary)

                ForEach(sources, id: \.address) { source in
                    if let url = URL(string: source.address) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Link(source.title, destination: url)
                                .tapTarget()
                            Text(source.scope)
                                .font(.callout)
                                .foregroundStyle(Theme.Ink.secondary)
                        }
                    }
                }
            }
            .padding(.top, Theme.Spacing.close)
        }
        .tint(Theme.Accent.brandText)
    }

    private var sources: [Source] {
        var sources = [Source(
            title: "Effect of breathwork on stress and mental health (2023)",
            scope: "A review of multiple breathing methods. It does not establish a benefit for every pattern in önd.",
            address: "https://www.nature.com/articles/s41598-022-27247-y"
        )]

        if let specific {
            sources.insert(specific, at: 0)
        }
        if technique.slug.rawValue == "extended-exhale" {
            sources.insert(Source(
                title: "Slow breathing for reducing stress: the effect of extending exhale (2023)",
                scope: "A 12-week trial in 100 adults found no clear advantage for longer exhales over equal counts.",
                address: "https://pubmed.ncbi.nlm.nih.gov/36871835/"
            ), at: 1)
        }
        if technique.slug.rawValue == "alternate-nostril" {
            sources.insert(Source(
                title: "Alternate-nostril breathing before public speaking (2017)",
                scope: "A small study found no clear anxiety benefit after a brief practice.",
                address: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5660749/"
            ), at: 1)
        }
        return sources
    }

    private var specific: Source? {
        switch technique.slug.rawValue {
        case "box-breathing", "long-box-breathing", "cyclic-sighing", "physiological-sigh":
            Source(
                title: "Brief structured respiration practices enhance mood and reduce physiological arousal (2023)",
                scope: "Compared daily five-minute practices. It does not test two sighs, six-count boxes or every timing used in önd.",
                address: "https://pmc.ncbi.nlm.nih.gov/articles/PMC9873947/"
            )
        case "coherent-breathing":
            Source(
                title: "Coherent breathing: a randomised placebo-controlled trial (2023)",
                scope: "Compared coherent breathing with a credible breathing control in 400 adults.",
                address: "https://www.nature.com/articles/s41598-023-49279-8"
            )
        case "four-seven-eight":
            Source(
                title: "4-7-8 breathing in people with tinnitus (2026)",
                scope: "A clinical-population trial. It does not establish improved sleep in healthy people.",
                address: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12895279/"
            )
        case "extended-exhale":
            Source(
                title: "Breathing pace and ratio study (2024)",
                scope: "Examined pace and ratio separately; supports caution about claims for a particular ratio.",
                address: "https://onlinelibrary.wiley.com/doi/10.1002/smi.3496"
            )
        case "wim-hof-rounds":
            Source(
                title: "High-ventilation breathwork: a placebo-controlled trial (2024)",
                scope: "A trial in 200 adults with a gentler comparison. Wider benefits remain uncertain.",
                address: "https://www.nature.com/articles/s41598-024-64254-7"
            )
        case "humming-breath":
            Source(
                title: "Humming greatly increases nasal nitric oxide (2002)",
                scope: "A physiological measurement, not evidence of an improvement in mood or health.",
                address: "https://pubmed.ncbi.nlm.nih.gov/12119224/"
            )
        case "pursed-lip-breathing":
            Source(
                title: "Breathing techniques in serious respiratory illness (2024)",
                scope: "A review of 73 trials in respiratory illness; general calm in healthy people was not established.",
                address: "https://publications.ersnet.org/content/errev/33/174/240012"
            )
        case "cooling-breath":
            Source(
                title: "Sheetali breathing in people with hypertension (2020)",
                scope: "A three-month trial in 100 people with high blood pressure; not a study of whole-body cooling.",
                address: "https://pubmed.ncbi.nlm.nih.gov/32379673/"
            )
        case "bellows-breath":
            Source(
                title: "Reaction time after yoga bellows-type breathing (2018)",
                scope: "Studied 25 healthy women in 18-minute sessions. It does not validate önd's brief round.",
                address: "https://pubmed.ncbi.nlm.nih.gov/30233116/"
            )
        case "alternate-nostril":
            Source(
                title: "Alternate-nostril breathing and blood pressure (2024)",
                scope: "A review found lower blood pressure, with large differences between studies. It does not establish a focus benefit.",
                address: "https://pubmed.ncbi.nlm.nih.gov/39008954/"
            )
        default: nil
        }
    }
}
