import OndKit

extension TransportFault {
    /// A stand-in fault for the many tests that drive a transport failure down
    /// some path without caring which failure it was.
    ///
    /// `.unreachable` because it is the one these tests are almost always
    /// standing in for — a server that is not there. A test that is about the
    /// classification builds the fault itself.
    static func stub(_ diagnostic: String = "offline") -> TransportFault {
        TransportFault(outcome: .unreachable, diagnostic: diagnostic)
    }
}
