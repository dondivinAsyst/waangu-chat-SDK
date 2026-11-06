import Testing
@testable import WaanguNetworkKit

@Suite("NetworkKit")
struct NetworkKitTests {

    @Test("RequestPriority provides correct QoS")
    func requestPriorityQoS() {
        #expect(RequestPriority.critical.qos == .userInteractive)
        #expect(RequestPriority.background.qos == .background)
    }
}
