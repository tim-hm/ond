import OndStyle
import OndUI
import SwiftUI

struct AmbientOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(
            minimumInterval: Theme.Motion.restfulFrameInterval,
            paused: reduceMotion || scenePhase != .active
        )) { context in
            let elapsed = reduceMotion ? AmbientBreath.restingCycle / 4
                : max(0, context.date.timeIntervalSince(startedAt))
            let level = AmbientBreath.fullness(at: elapsed, cycle: AmbientBreath.restingCycle)

            SmokeOrb(
                scale: AirOrbMotion.scale(forLevel: level),
                swirl: reduceMotion ? 0 : AmbientBreath.airflow(at: elapsed),
                side: 260
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("welcome-breath-guide")
        .accessibilityLabel("Guided breath")
        .accessibilityValue(
            reduceMotion ? "Breathe in" : "Breathing in and out for five and a half seconds each"
        )
    }
}
