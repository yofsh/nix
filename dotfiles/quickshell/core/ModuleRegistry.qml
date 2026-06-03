pragma Singleton

import QtQuick
import Quickshell
import "." as Core

// Modules are statically linked (BarHost widgets/popups, ServiceHost services), so
// this is no longer a discovery/loader registry — it just tracks live instances so
// popups can find their driving widget and `context.service` can resolve, plus a
// thin passthrough to per-module config.
Scope {
    id: root

    property var widgetInstances: ({})
    property int widgetRevision: 0

    property var serviceInstances: ({})
    property int serviceRevision: 0

    property var windowInstances: ({})
    property int windowRevision: 0

    function packageConfig(id, defaults) {
        return Core.ConfigService.packageConfig(id, defaults || {});
    }

    function instanceKey(moduleId, screenName) {
        return moduleId + "|" + (screenName || "global");
    }

    // -- widget instances (per screen) --------------------------------------

    function registerWidgetInstance(moduleId, screenName, instance) {
        var next = Object.assign({}, widgetInstances);
        next[instanceKey(moduleId, screenName)] = instance;
        widgetInstances = next;
        widgetRevision += 1;
    }

    function unregisterWidgetInstance(moduleId, screenName) {
        var key = instanceKey(moduleId, screenName);
        if (!(key in widgetInstances))
            return;
        var next = Object.assign({}, widgetInstances);
        delete next[key];
        widgetInstances = next;
        widgetRevision += 1;
    }

    function widgetInstance(moduleId, screenName) {
        widgetRevision;
        return widgetInstances[instanceKey(moduleId, screenName)] || null;
    }

    // -- service instances (global) -----------------------------------------

    function registerServiceInstance(moduleId, instance) {
        var next = Object.assign({}, serviceInstances);
        next[moduleId] = instance;
        serviceInstances = next;
        serviceRevision += 1;
    }

    function unregisterServiceInstance(moduleId) {
        if (!(moduleId in serviceInstances))
            return;
        var next = Object.assign({}, serviceInstances);
        delete next[moduleId];
        serviceInstances = next;
        serviceRevision += 1;
    }

    function serviceInstance(moduleId) {
        serviceRevision;
        return serviceInstances[moduleId] || null;
    }

    // -- window instances (per screen) --------------------------------------

    function registerWindowInstance(moduleId, screenName, instance) {
        var next = Object.assign({}, windowInstances);
        next[instanceKey(moduleId, screenName)] = instance;
        windowInstances = next;
        windowRevision += 1;
    }

    function unregisterWindowInstance(moduleId, screenName) {
        var key = instanceKey(moduleId, screenName);
        if (!(key in windowInstances))
            return;
        var next = Object.assign({}, windowInstances);
        delete next[key];
        windowInstances = next;
        windowRevision += 1;
    }

    function windowInstance(moduleId, screenName) {
        windowRevision;
        return windowInstances[instanceKey(moduleId, screenName)] || null;
    }
}
