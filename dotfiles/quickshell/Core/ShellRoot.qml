//@ pragma IconTheme Papirus
import Quickshell
import "." as Core
import "../popups" as Popups

Scope {
    id: root

    Core.ModuleScanner {}
    Core.ServiceHost {}

    Popups.PolkitPopup {
        id: polkitPopup
        barHeight: Core.ConfigService.section("theme", {}).barHeight || 22
    }

    Variants {
        model: Quickshell.screens

        Core.BarHost {
            required property var modelData
            screen: modelData
            polkitActive: polkitPopup.active
        }
    }
}
