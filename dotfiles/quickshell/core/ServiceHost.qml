import Quickshell
import QtQuick
import "." as Core
import "../modules/focus" as M_focus
import "../modules/khal" as M_khal
import "../modules/network" as M_network
import "../modules/ping" as M_ping
import "../modules/recordborder" as M_recordborder

// Statically instantiates the modules that have a Service.qml (global, screen-less).
// PackageService registers each instance so `context.service` resolves for widgets.
Scope {
    Core.PackageService { moduleId: "focus";   M_focus.Service {} }
    Core.PackageService { moduleId: "khal";    M_khal.Service {} }
    Core.PackageService { moduleId: "network"; M_network.Service {} }
    Core.PackageService { moduleId: "ping";    M_ping.Service {} }
    Core.PackageService { moduleId: "recordborder"; M_recordborder.Service {} }
}
