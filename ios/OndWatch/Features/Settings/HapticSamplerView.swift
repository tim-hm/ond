#if DEBUG
    import SwiftUI
    import WatchKit

    /// Every public watch haptic worth comparing, kept out of release builds.
    ///
    /// The simulator renders none of these. This screen exists to answer on a
    /// wrist which predefined WatchKit pattern and which SwiftUI impact survive
    /// a sleeve, whether SwiftUI honours intensity, and which choice stays
    /// neutral enough to repeat through a breathing phase.
    struct HapticSamplerView: View {
        var body: some View {
            List {
                Section("WatchKit") {
                    watchKitButton("Click", haptic: .click)
                    watchKitButton("Direction up", haptic: .directionUp)
                    watchKitButton("Direction down", haptic: .directionDown)
                    watchKitButton("Start", haptic: .start)
                    watchKitButton("Stop", haptic: .stop)
                    watchKitButton("Notification", haptic: .notification)
                    watchKitButton("Success", haptic: .success)
                    watchKitButton("Failure", haptic: .failure)
                    watchKitButton("Retry", haptic: .retry)
                }

                Section("Navigation") {
                    watchKitButton("Maneuver", haptic: .navigationGenericManeuver)
                    watchKitButton("Left turn", haptic: .navigationLeftTurn)
                    watchKitButton("Right turn", haptic: .navigationRightTurn)
                }

                Section("Depth") {
                    watchKitButton("Depth prompt", haptic: .underwaterDepthPrompt)
                    watchKitButton("Depth critical", haptic: .underwaterDepthCriticalPrompt)
                }

                Section("SwiftUI weight") {
                    SensoryFeedbackButton("Default", feedback: .impact)
                    SensoryFeedbackButton("Light", feedback: .impact(weight: .light))
                    SensoryFeedbackButton("Medium", feedback: .impact(weight: .medium))
                    SensoryFeedbackButton("Heavy", feedback: .impact(weight: .heavy))
                }

                Section("SwiftUI flexibility") {
                    SensoryFeedbackButton("Soft", feedback: .impact(flexibility: .soft))
                    SensoryFeedbackButton("Solid", feedback: .impact(flexibility: .solid))
                    SensoryFeedbackButton("Rigid", feedback: .impact(flexibility: .rigid))
                }

                Section("SwiftUI intensity") {
                    SensoryFeedbackButton(
                        "Medium · 35%",
                        feedback: .impact(weight: .medium, intensity: 0.35)
                    )
                    SensoryFeedbackButton(
                        "Medium · 100%",
                        feedback: .impact(weight: .medium, intensity: 1)
                    )
                    SensoryFeedbackButton(
                        "Heavy · 35%",
                        feedback: .impact(weight: .heavy, intensity: 0.35)
                    )
                    SensoryFeedbackButton(
                        "Heavy · 100%",
                        feedback: .impact(weight: .heavy, intensity: 1)
                    )
                }

                Section("SwiftUI meaning") {
                    SensoryFeedbackButton("Selection", feedback: .selection)
                    SensoryFeedbackButton("Alignment", feedback: .alignment)
                    SensoryFeedbackButton("Level change", feedback: .levelChange)
                    SensoryFeedbackButton("Path complete", feedback: .pathComplete)
                    SensoryFeedbackButton("Increase", feedback: .increase)
                    SensoryFeedbackButton("Decrease", feedback: .decrease)
                    SensoryFeedbackButton("Start", feedback: .start)
                    SensoryFeedbackButton("Stop", feedback: .stop)
                    SensoryFeedbackButton("Success", feedback: .success)
                    SensoryFeedbackButton("Warning", feedback: .warning)
                    SensoryFeedbackButton("Error", feedback: .error)
                }
            }
            .navigationTitle("Haptics")
        }

        /// Plays one of WatchKit's fixed hardware patterns immediately.
        ///
        /// - Parameters:
        ///   - title: The vocabulary shown for the pattern.
        ///   - haptic: The public system pattern to render.
        /// - Returns: A button suitable for this sampler's list.
        private func watchKitButton(_ title: String, haptic: WKHapticType) -> some View {
            Button(title) {
                WKInterfaceDevice.current().play(haptic)
            }
        }
    }

    /// A button whose state change gives SwiftUI a fresh feedback trigger.
    ///
    /// Kept as a view rather than an action closure because `sensoryFeedback`
    /// observes a value in a view hierarchy; it is not an imperative engine the
    /// session controller can call directly.
    private struct SensoryFeedbackButton: View {
        private let title: String
        private let feedback: SensoryFeedback
        @State private var trigger = 0

        /// Creates one independently-triggered SwiftUI haptic sample.
        ///
        /// - Parameters:
        ///   - title: The vocabulary shown for the sample.
        ///   - feedback: The public SwiftUI feedback to render.
        init(_ title: String, feedback: SensoryFeedback) {
            self.title = title
            self.feedback = feedback
        }

        var body: some View {
            Button(title) {
                trigger += 1
            }
            .sensoryFeedback(feedback, trigger: trigger)
        }
    }
#endif
