import OndUI
import SwiftUI

struct SessionGround: ViewModifier {
    private static let deep = Color(red: 0x05 / 255, green: 0x09 / 255, blue: 0x0B / 255)

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Self.deep.ignoresSafeArea()
                    AmbientField(date: Date(timeIntervalSinceReferenceDate: 0)).ignoresSafeArea()
                }
            }
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func sessionGround() -> some View {
        modifier(SessionGround())
    }
}
