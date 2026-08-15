//! Shared conversions between the technique domain vocabulary and its wire
//! enums.
//!
//! Every mapping is exhaustive in the domain direction so adding a database
//! value without adding its protobuf counterpart fails at compile time. The
//! inbound mappings reject both protobuf zero values and unknown future values;
//! each calling feature remains responsible for wording that refusal.

use super::types::{CopyRegister, DeliverySurface, Passage, PhaseKind, TechniqueGoal};
use crate::proto::ond::v1 as pb;

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
