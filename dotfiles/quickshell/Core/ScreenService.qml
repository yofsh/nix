pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

QtObject {
    id: root

    readonly property string activeScreenName: {
        var focusedMonitor = Hyprland.focusedMonitor;
        if (focusedMonitor && focusedMonitor.name)
            return focusedMonitor.name;

        var screens = Quickshell.screens;
        return screens.length > 0 && screens[0].name ? screens[0].name : "global";
    }

    readonly property var activeScreen: {
        var screens = Quickshell.screens;
        var name = activeScreenName;

        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }

        return screens.length > 0 ? screens[0] : null;
    }
}
