//@ pragma IconTheme Papirus
import Quickshell
import Quickshell.Io
import QtQuick
import "." as Core
import "../popups" as Popups
import "../config" as AppConfig

Scope {
    id: root

    Core.ServiceHost {}

    QtObject {
        id: fingerprintBus
        signal fingerprintLine(string data)
    }

    Process {
        id: fingerprintDbusProc
        command: ["dbus-monitor", "--system", "type='signal',interface='net.reactivated.Fprint.Device'"]
        running: true
        stdout: SplitParser {
            onRead: data => fingerprintBus.fingerprintLine(data)
        }
    }

    Popups.PolkitPopup {
        id: polkitPopup
        barHeight: AppConfig.Config.theme.barHeight
        fingerprintMonitor: fingerprintBus
    }

    Variants {
        model: Quickshell.screens

        Core.BarHost {
            required property var modelData
            screen: modelData
            polkitActive: polkitPopup.active
            fingerprintMonitor: fingerprintBus
        }
    }
}
