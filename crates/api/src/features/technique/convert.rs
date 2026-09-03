//! Shared conversions between the technique domain vocabulary and its wire enums.
//!
//! Every mapping is exhaustive in the domain direction, so a database value with no protobuf
//! counterpart fails at compile time. Inbound mappings reject zero values and unknown future
//! values alike; each calling feature words that refusal itself.

use super::types::{
    CopyRegister, DeliverySurface, EvidenceGrade, Manner, Passage, PhaseKind, PlayablePhase,
    ReadingContent, ReadingListStyle, TechniqueGoal,
};
use crate::proto::ond::v1 as pb;
use crate::wire;

/// A domain goal as the protobuf vocabulary shared by catalogue, profile, and
/// authored exercises.
pub(crate) const fn goal_to_proto(goal: TechniqueGoal) -> pb::TechniqueGoal {
    match goal {
        TechniqueGoal::Calm => pb::TechniqueGoal::Calm,
        TechniqueGoal::Sleep => pb::TechniqueGoal::Sleep,
        TechniqueGoal::Energy => pb::TechniqueGoal::Energy,
        TechniqueGoal::Reset => pb::TechniqueGoal::Reset,
        TechniqueGoal::Focus => pb::TechniqueGoal::Focus,
    }
}

/// A protobuf goal when it names a domain value.
///
/// `None` covers both the zero value and anything a newer client invents, so
/// callers cannot silently widen the vocabulary at different boundaries.
pub(crate) fn goal_from_proto(raw: i32) -> Option<TechniqueGoal> {
    match pb::TechniqueGoal::try_from(raw) {
        Ok(pb::TechniqueGoal::Calm) => Some(TechniqueGoal::Calm),
        Ok(pb::TechniqueGoal::Sleep) => Some(TechniqueGoal::Sleep),
        Ok(pb::TechniqueGoal::Energy) => Some(TechniqueGoal::Energy),
        Ok(pb::TechniqueGoal::Reset) => Some(TechniqueGoal::Reset),
        Ok(pb::TechniqueGoal::Focus) => Some(TechniqueGoal::Focus),
        Ok(pb::TechniqueGoal::Unspecified) | Err(_) => None,
    }
}

/// A session presentation surface as its protobuf value.
pub(crate) const fn surface_to_proto(surface: DeliverySurface) -> pb::DeliverySurface {
    match surface {
        DeliverySurface::FullScreen => pb::DeliverySurface::FullScreen,
        DeliverySurface::Discreet => pb::DeliverySurface::Discreet,
    }
}

/// An occasion's copy register as its protobuf value.
pub(super) const fn register_to_proto(register: CopyRegister) -> pb::CopyRegister {
    match register {
        CopyRegister::Plain => pb::CopyRegister::Plain,
        CopyRegister::Playful => pb::CopyRegister::Playful,
    }
}

/// How well evidenced an exercise is, as its protobuf value.
///
/// `Unspecified` is legitimate output, on `passage_to_proto`'s terms: a technique with no grade
/// is one nobody trialled — every exercise somebody wrote themselves — and the client draws
/// nothing rather than reading a default off the zero value.
pub(crate) const fn evidence_grade_to_proto(grade: Option<EvidenceGrade>) -> pb::EvidenceGrade {
    match grade {
        Some(EvidenceGrade::Moderate) => pb::EvidenceGrade::Moderate,
        Some(EvidenceGrade::Limited) => pb::EvidenceGrade::Limited,
        None => pb::EvidenceGrade::Unspecified,
    }
}

/// A reading list style as the wire vocabulary shared by exercises and
/// foundations.
pub(super) const fn reading_list_style_to_proto(style: ReadingListStyle) -> pb::ReadingListStyle {
    match style {
        ReadingListStyle::None => pb::ReadingListStyle::Unspecified,
        ReadingListStyle::Bullets => pb::ReadingListStyle::Bullets,
        ReadingListStyle::Numbered => pb::ReadingListStyle::Numbered,
    }
}

/// Structured catalogue copy as its wire representation.
pub(super) fn reading_content_to_proto(content: ReadingContent) -> pb::ReadingContent {
    pb::ReadingContent {
        lead: content.lead,
        items: content.items,
        list_style: reading_list_style_to_proto(content.list_style) as i32,
    }
}

/// A domain phase kind as its protobuf value.
pub(crate) const fn phase_kind_to_proto(kind: PhaseKind) -> pb::PhaseKind {
    match kind {
        PhaseKind::Inhale => pb::PhaseKind::Inhale,
        PhaseKind::HoldIn => pb::PhaseKind::HoldIn,
        PhaseKind::Exhale => pb::PhaseKind::Exhale,
        PhaseKind::HoldOut => pb::PhaseKind::HoldOut,
    }
}

/// A breathing passage as its protobuf value, or zero for a hold.
///
/// Passage is the one wire enum where `Unspecified` is legitimate output: a
/// hold has no air path, while `Phase` cannot omit the scalar field.
pub(crate) const fn passage_to_proto(passage: Option<Passage>) -> pb::Passage {
    match passage {
        Some(Passage::Nose) => pb::Passage::Nose,
        Some(Passage::Mouth) => pb::Passage::Mouth,
        Some(Passage::LeftNostril) => pb::Passage::LeftNostril,
        Some(Passage::RightNostril) => pb::Passage::RightNostril,
        None => pb::Passage::Unspecified,
    }
}

/// A breath's shape as its protobuf value, or zero where it has none.
///
/// `Unspecified` is ordinary output here, unlike the pointed zero `passage_to_proto` produces for
/// a hold: most phases are shaped no particular way. There is no inbound half — the composer has
/// no field for a manner, so `manner_from_proto` would be dead code under `-D warnings`.
pub(crate) const fn manner_to_proto(manner: Option<Manner>) -> pb::Manner {
    match manner {
        Some(Manner::CurledTongue) => pb::Manner::CurledTongue,
        Some(Manner::PursedLips) => pb::Manner::PursedLips,
        Some(Manner::Hum) => pb::Manner::Hum,
        None => pb::Manner::Unspecified,
    }
}

/// The one place a phase becomes its wire message. The curated catalogue and
/// an exercise somebody authored both serve through it, so a field added to
/// `Phase` cannot be filled on one path and left as a zero on the other. Every
/// count narrows here; the schema's `CHECK`s make a failed narrowing corrupt
/// data rather than a client's fault.
pub(crate) fn phase_to_proto(phase: PlayablePhase) -> Result<pb::Phase, wire::Unrepresentable> {
    Ok(pb::Phase {
        kind: phase_kind_to_proto(phase.kind) as i32,
        duration_ms: wire::positive("phase duration", phase.duration_ms)?,
        min_duration_ms: wire::positive("phase minimum", phase.min_duration_ms)?,
        max_duration_ms: wire::positive("phase maximum", phase.max_duration_ms)?,
        passage: passage_to_proto(phase.passage) as i32,
        manner: manner_to_proto(phase.manner) as i32,
        // `counted` rather than `positive`: an authored zero says this rhythm
        // turns without a gap, which is what a continuous exercise means. The
        // 0–600 ms bound is the column's, and presence is what carries the
        // distinction a bare zero could not.
        turn_gap_ms: phase
            .turn_gap_ms
            .map(|gap| wire::counted("phase turn gap", gap))
            .transpose()?,
        haptic_pattern: phase.haptic_pattern,
    })
}

/// A protobuf passage when it names an air path.
///
/// Holds are represented by their movement arm before this conversion is
/// called, so both zero and unknown values are refusals here.
pub(crate) fn passage_from_proto(raw: i32) -> Option<Passage> {
    match pb::Passage::try_from(raw) {
        Ok(pb::Passage::Nose) => Some(Passage::Nose),
        Ok(pb::Passage::Mouth) => Some(Passage::Mouth),
        Ok(pb::Passage::LeftNostril) => Some(Passage::LeftNostril),
        Ok(pb::Passage::RightNostril) => Some(Passage::RightNostril),
        Ok(pb::Passage::Unspecified) | Err(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_domain_goal_maps_to_unspecified() {
        for goal in [
            TechniqueGoal::Calm,
            TechniqueGoal::Sleep,
            TechniqueGoal::Energy,
            TechniqueGoal::Reset,
            TechniqueGoal::Focus,
        ] {
            assert_ne!(goal_to_proto(goal), pb::TechniqueGoal::Unspecified);
        }
    }

    #[test]
    fn only_a_hold_maps_to_an_unspecified_passage() {
        for passage in [
            Passage::Nose,
            Passage::Mouth,
            Passage::LeftNostril,
            Passage::RightNostril,
        ] {
            assert_ne!(passage_to_proto(Some(passage)), pb::Passage::Unspecified);
            assert_eq!(
                passage_from_proto(passage_to_proto(Some(passage)) as i32),
                Some(passage)
            );
        }
        assert_eq!(passage_to_proto(None), pb::Passage::Unspecified);
    }

    /// The same shape as the passage rule above, minus the round trip — there is
    /// no inbound half to round-trip through, and that absence is the point:
    /// nothing sends a manner, so the mapping is one-way by design rather than
    /// by omission.
    #[test]
    fn only_an_unshaped_breath_maps_to_an_unspecified_manner() {
        for manner in [Manner::CurledTongue, Manner::PursedLips, Manner::Hum] {
            assert_ne!(manner_to_proto(Some(manner)), pb::Manner::Unspecified);
        }
        assert_eq!(manner_to_proto(None), pb::Manner::Unspecified);
    }

    #[test]
    fn no_domain_surface_maps_to_unspecified() {
        for surface in [DeliverySurface::FullScreen, DeliverySurface::Discreet] {
            assert_ne!(
                surface_to_proto(surface),
                pb::DeliverySurface::Unspecified,
                "{surface:?}"
            );
        }
    }

    /// Both halves, because this is the one conversion where unspecified is a
    /// real answer as well as a failure: an ungraded exercise must reach the
    /// wire as zero, and a graded one must never.
    #[test]
    fn only_an_ungraded_technique_maps_to_unspecified() {
        for grade in [EvidenceGrade::Moderate, EvidenceGrade::Limited] {
            assert_ne!(
                evidence_grade_to_proto(Some(grade)),
                pb::EvidenceGrade::Unspecified,
                "{grade:?}"
            );
        }

        assert_eq!(
            evidence_grade_to_proto(None),
            pb::EvidenceGrade::Unspecified
        );
    }

    #[test]
    fn no_domain_register_maps_to_unspecified() {
        for register in [CopyRegister::Plain, CopyRegister::Playful] {
            assert_ne!(
                register_to_proto(register),
                pb::CopyRegister::Unspecified,
                "{register:?}"
            );
        }
    }

    #[test]
    fn no_domain_phase_kind_maps_to_unspecified() {
        for kind in [
            PhaseKind::Inhale,
            PhaseKind::HoldIn,
            PhaseKind::Exhale,
            PhaseKind::HoldOut,
        ] {
            assert_ne!(phase_kind_to_proto(kind), pb::PhaseKind::Unspecified);
        }
    }
}
