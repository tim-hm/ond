import XCTest

extension XCTestCase {
    /// Waits for a screen to have arrived, then attaches the whole screen.
    /// The anchor is the point: a timer-driven capture eventually ships a
    /// shot of a spinner, and nothing about the PNG says so. On `XCTestCase`
    /// so every screenshot class attaches the same way. `name` becomes the
    /// exported filename and so the set's order; `fallback` covers a conditional anchor.
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
