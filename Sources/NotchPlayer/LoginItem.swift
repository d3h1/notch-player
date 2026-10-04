import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NotchPlayer: could not update login item: %@", error.localizedDescription)
        }
        NSLog("NotchPlayer: open at login is %@", isEnabled ? "on" : "off")
    }
}
