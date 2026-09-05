import OndKit
import OndStyle
import OndUI
import SwiftUI

struct SessionView: View {
    @State private var model: SessionModel
    @State private var runtime = ExtendedRuntime()
    @State private var isPrepared = false
    @State private var readyIn = 3
    @State private var isRetrying = false

    @Environment(TechniqueWarningStore.self) private var warnings

    /// Whether the caution was answered on this run. Separate from the store,
    /// which only remembers a silence: an acceptance without one covers this
    /// session, and re-reading the store would put the screen straight back.
    @State private var hasAcceptedWarning = false

    /// Called once a finished session has been read and acknowledged, which is
    /// where the wrist's recordings get their chance to reach the server. Here
    /// rather than on the way out of the catalogue, so the drain cannot start
    /// its RPC in the same instant the extended runtime session does.
    private let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(model: SessionModel, onFinished: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        Group {
            if let warning = pendingWarning {
                WristWarningView(warning: warning) { silenced in
                    warnings.accept(warning, silenced: silenced)
                    hasAcceptedWarning = true
                } onDeclined: {
                    dismiss()
                }
            } else if model.status == .finished, let record = model.record {
                SessionSummaryView(
                    outcome: model.wasDiscarded ? .discarded : .kept(record),
                    technique: model.technique,
                    register: model.timeline.register,
                    reached: model.reachedStage
                ) {
                    onFinished()
                    dismiss()
                }
            } else if runtime.state == .unavailable || isRetrying {
                runtimeRecovery
            } else if !isPrepared {
                preparation
            } else {
                WatchSessionPlayerView(model: model)
            }
        }
        .wristGround(ground)
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden)
        .task(id: pendingWarning) { await prepare() }
        .onDisappear {
            runtime.invalidate()
            model.dismiss()
        }
        .onChange(of: model.status) { _, status in
            guard status == .finished else { return }
            // The budget goes back the moment the breathing ends, not when the
            // screen does — a summary being read needs no runtime session.
            runtime.invalidate()
        }
        .onChange(of: model.currentBeat?.id) { _, _ in announceCurrentPhase() }
        .onChange(of: runtime.state) { _, state in
            if state == .unavailable {
                isRetrying = false
                model.pause()
            } else if state == .running, isRetrying {
                isRetrying = false
                model.resume()
            }
        }
    }

    private var pendingWarning: SessionWarning? {
        guard !hasAcceptedWarning,
              let warning = model.warning,
              warnings.needsWarning(for: warning)
        else { return nil }
        return warning
    }

    private func begin() {
        guard pendingWarning == nil, !isPrepared else { return }
        isPrepared = true
        #if DEBUG
            if WatchSessionPreview.slug != nil {
                model.start()
                return
            }
        #endif
        runtime.start()
        model.start()
    }

    private func prepare() async {
        guard pendingWarning == nil, !isPrepared else { return }
        for second in (1 ... 3).reversed() {
            guard !isPrepared, !Task.isCancelled else { return }
            readyIn = second
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        begin()
    }

    private var preparation: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.close) {
                Text("Get comfortable").font(.headline)
                Text("Starting in \(readyIn)").font(.body).monospacedDigit()
                Button("Start now", action: begin)
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var runtimeRecovery: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.close) {
                Text("Practice paused").font(.headline)
                Text(
                    "Your watch could not keep guidance running. Breathe normally while you retry."
                )
                .font(.caption)
                Button(isRetrying ? "Starting…" : "Retry guidance") {
                    isRetrying = true
                    runtime.start()
                }
                .disabled(isRetrying)
                Button("End practice") { model.end() }
            }
        }
    }

    /// Black air for the live breath, the session's wash for the summary. Black
    /// through the same modifier rather than a special case: black's gradient
    /// at the wash's strength is still black, so one line gives the player
    /// its deep ground and the summary its accent.
    private var ground: Color {
        model.status == .finished ? model.accent : .black
    }

    /// What VoiceOver is told when the breath changes. The phase element
    /// updates its label, but a label changing under an element nobody is
    /// focused on is never spoken — turning the taps off left the session
    /// silent to VoiceOver. Unlike the phone there is nothing to suppress
    /// against: the wrist plays no clips.
    private func announceCurrentPhase() {
        guard let beat = model.currentBeat else { return }
        AccessibilityNotification.Announcement(spokenAnnouncement(for: beat)).post()
    }

    private func spokenAnnouncement(for beat: SessionTimeline.Beat) -> String {
        guard let target = beat.target else { return beat.spokenInstruction }
        let length = target.formatted(.time(pattern: .minuteSecond))
        return "\(beat.spokenInstruction). Aim for \(length)."
    }
}
