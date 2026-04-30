import Foundation
import IOKit.pwr_mgt

final class DisplaySleepBlocker: ObservableObject {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    func start() {
        guard !isActive else { return }
        let reason = "Csopak Beach Cam is playing video" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        stop()
    }
}
