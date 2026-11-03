import Foundation
import Testing
@testable import LocalSTTCore

@Suite("DeviceSelectionPolicy")
struct DeviceSelectionPolicyTests {

    @Test("A stored device that is still present takes priority")
    func prefersSavedDevice() {
        let selection = DeviceSelectionPolicy.resolve(
            saved: "scarlett",
            available: ["builtin", "scarlett"],
            systemDefault: "builtin"
        )
        #expect(selection == "scarlett")
    }

    @Test("A stored device that is no longer attached gives way to the system default")
    func fallsBackWhenSavedDeviceIsGone() {
        let selection = DeviceSelectionPolicy.resolve(
            saved: "scarlett",
            available: ["builtin"],
            systemDefault: "builtin"
        )
        #expect(selection == "builtin")
    }

    @Test("Absent a stored choice, the system default applies")
    func usesSystemDefaultWhenNothingSaved() {
        let selection = DeviceSelectionPolicy.resolve(
            saved: nil,
            available: ["builtin", "scarlett"],
            systemDefault: "scarlett"
        )
        #expect(selection == "scarlett")
    }

    @Test("A system default that is missing yields the first available device")
    func fallsBackToFirstDevice() {
        let selection = DeviceSelectionPolicy.resolve(
            saved: nil,
            available: ["builtin", "scarlett"],
            systemDefault: "airpods"
        )
        #expect(selection == "builtin")
    }

    @Test("Zero input devices produce an empty selection")
    func returnsEmptyWhenNothingAvailable() {
        let selection = DeviceSelectionPolicy.resolve(
            saved: "scarlett",
            available: [],
            systemDefault: "builtin"
        )
        #expect(selection.isEmpty)
    }
}
