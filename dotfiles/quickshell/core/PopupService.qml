pragma Singleton

import QtQuick

QtObject {
    id: root

    property var openState: ({})
    property int revision: 0

    function stateKey(moduleId, screenName) {
        return moduleId + "|" + (screenName || "global");
    }

    function isOpen(moduleId, screenName) {
        return !!openState[stateKey(moduleId, screenName)];
    }

    function setOpen(moduleId, screenName, open) {
        var key = stateKey(moduleId, screenName);
        var current = !!openState[key];
        var nextOpen = !!open;

        if (current === nextOpen)
            return;

        var next = Object.assign({}, openState);
        if (nextOpen)
            next[key] = true;
        else
            delete next[key];

        openState = next;
        revision += 1;
    }

    function open(moduleId, screenName) {
        setOpen(moduleId, screenName, true);
    }

    function close(moduleId, screenName) {
        setOpen(moduleId, screenName, false);
    }

    function toggle(moduleId, screenName) {
        setOpen(moduleId, screenName, !isOpen(moduleId, screenName));
    }
}
