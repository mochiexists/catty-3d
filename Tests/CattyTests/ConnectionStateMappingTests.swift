// Locks the SSHTransport.ConnectionState → CattyConnectionState 1:1
// mapping. These are deliberately-separate enums (the transport-neutral
// SSH seam), so the mapping is hand-written boilerplate that MUST stay
// exhaustive and identity-preserving. The OSS DRY review flagged it as
// load-bearing duplication to keep — these tests guard it instead of
// collapsing it.

@testable import Catty
import XCTest

final class ConnectionStateMappingTests: XCTestCase {

    func testEveryCaseMapsToItsCattyEquivalent() {
        XCTAssertEqual(SSHTransport.ConnectionState.idle.cattyMapping, .idle)
        XCTAssertEqual(SSHTransport.ConnectionState.connecting.cattyMapping, .connecting)
        XCTAssertEqual(SSHTransport.ConnectionState.authenticating.cattyMapping, .authenticating)
        XCTAssertEqual(SSHTransport.ConnectionState.connected.cattyMapping, .connected)
    }

    func testDisconnectedReasonPassesThrough() {
        XCTAssertEqual(
            SSHTransport.ConnectionState.disconnected(nil).cattyMapping,
            CattyConnectionState.disconnected(nil)
        )
        XCTAssertEqual(
            SSHTransport.ConnectionState.disconnected("auth failed").cattyMapping,
            CattyConnectionState.disconnected("auth failed")
        )
    }
}
