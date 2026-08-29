/// Waits for a model's reader task to catch up, polling until `condition` holds
/// or two seconds pass — a fixed nap loses the race on a loaded machine, where a
/// model's publishing `Task` can miss its slice for tens of milliseconds. Wait
/// on something weaker than the assertion that follows, or the wait swallows the
/// failure it exists to report. Gives up, letting the assertion state the facts.
@MainActor
func settle(until condition: @MainActor () -> Bool) async throws {
    for _ in 0 ..< 400 {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
