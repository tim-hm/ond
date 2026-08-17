import XCTest

extension XCTestCase {
    /// Waits for a screen to have arrived, then attaches the whole screen.
    ///
    /// The anchor is the point: a screenshot harness that captures on a timer
    /// eventually ships a shot of a spinner, and nothing about the resulting
    /// PNG says it went wrong.
    ///
    /// On `XCTestCase` rather than in one of the two classes that call it, so
    /// the subscription pair and the listing set attach their shots the same
    /// way — they run as separate classes only because they need different
    /// launch arguments, which is not a reason to photograph differently.
    ///
    /// - Parameters:
    ///   - name: the attachment name, which becomes the exported filename and
    ///     therefore the set's running order.
    ///   - anchor: the element whose arrival means the screen is drawn.
    ///   - fallback: a second chance for a screen whose anchor is conditional.
    func capture(
        _ name: String,
        once anchor: XCUIElement,
        or fallback: XCUIElement? = nil
    ) {
        if !anchor.waitForExistence(timeout: 15) {
            guard let fallback, fallback.waitForExistence(timeout: 5) else {
                return XCTFail("\(name): the screen never arrived, so nothing was captured")
            }
        }

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        // Attachments are discarded on success by default, and every run of
        // this test is a success.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
