pragma Singleton

import QtQuick
import Quickshell
import "." as Core

Scope {
    id: root

    property string quickshellRoot: Qt.resolvedUrl("..").toString().replace("file://", "")

    property var packages: ({})
    property bool ready: false
    property int packagesRevision: 0

    property var widgetInstances: ({})
    property int widgetRevision: 0

    property var serviceInstances: ({})
    property int serviceRevision: 0

    property var windowInstances: ({})
    property int windowRevision: 0

    signal loaded()

    function packageById(id) {
        return packages[id] || null;
    }

    function packageConfig(id) {
        var pkg = packageById(id);
        var defaults = {};
        return Core.ConfigService.packageConfig(id, defaults);
    }

    function entryUrl(id, entryName) {
        var pkg = packageById(id);
        if (!pkg)
            return "";

        var fileMap = { widget: "Widget.qml", popup: "Popup.qml", service: "Service.qml" };
        var file = fileMap[entryName];
        if (!file)
            return "";

        if (entryName === "widget" && !pkg.hasWidget) return "";
        if (entryName === "popup" && !pkg.hasPopup) return "";
        if (entryName === "service" && !pkg.hasService) return "";

        return Qt.resolvedUrl("../" + pkg.basePath + "/" + file);
    }

    function allPackageIds() {
        packagesRevision;
        return Object.keys(packages);
    }

    function uniqueIds(ids) {
        var seen = {};
        var result = [];

        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            if (!id || seen[id])
                continue;
            seen[id] = true;
            result.push(id);
        }

        return result;
    }

    function barIds(section) {
        var bar = Core.ConfigService.section("bar", { left: [], center: [], right: [] });
        var ids = uniqueIds(bar[section] || []);
        var result = [];

        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            var pkg = packageById(id);
            if (!pkg || !pkg.hasWidget)
                continue;
            if (!Core.ConfigService.isPackageEnabled(id))
                continue;
            result.push(id);
        }

        return result;
    }

    function isInBar(id) {
        return barIds("left").indexOf(id) >= 0
            || barIds("center").indexOf(id) >= 0
            || barIds("right").indexOf(id) >= 0;
    }

    function popupIds() {
        var ids = allPackageIds();
        var result = [];

        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            var pkg = packageById(id);
            if (!pkg || !pkg.hasPopup)
                continue;
            if (!Core.ConfigService.isPackageEnabled(id))
                continue;

            var moduleConfig = Core.ConfigService.packageConfig(id, {});
            if (!isInBar(id) && moduleConfig.alwaysLoadPopup !== true)
                continue;

            result.push(id);
        }

        return result;
    }

    function serviceIds() {
        var ids = allPackageIds();
        var result = [];

        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            var pkg = packageById(id);
            if (!pkg)
                continue;
            if (!Core.ConfigService.isPackageEnabled(id))
                continue;
            // Modules with a Service.qml or a Popup.qml (popup gets auto-IPC)
            if (!pkg.hasService && !pkg.hasPopup)
                continue;

            result.push(id);
        }

        return result;
    }

    function widgetKey(moduleId, screenName) {
        return moduleId + "|" + (screenName || "global");
    }

    function registerWidgetInstance(moduleId, screenName, instance) {
        var next = Object.assign({}, widgetInstances);
        next[widgetKey(moduleId, screenName)] = instance;
        widgetInstances = next;
        widgetRevision += 1;
    }

    function unregisterWidgetInstance(moduleId, screenName) {
        var key = widgetKey(moduleId, screenName);
        if (!(key in widgetInstances))
            return;

        var next = Object.assign({}, widgetInstances);
        delete next[key];
        widgetInstances = next;
        widgetRevision += 1;
    }

    function widgetInstance(moduleId, screenName) {
        widgetRevision;
        return widgetInstances[widgetKey(moduleId, screenName)] || null;
    }

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

    function registerWindowInstance(moduleId, screenName, instance) {
        var next = Object.assign({}, windowInstances);
        next[widgetKey(moduleId, screenName)] = instance;
        windowInstances = next;
        windowRevision += 1;
    }

    function unregisterWindowInstance(moduleId, screenName) {
        var key = widgetKey(moduleId, screenName);
        if (!(key in windowInstances))
            return;

        var next = Object.assign({}, windowInstances);
        delete next[key];
        windowInstances = next;
        windowRevision += 1;
    }

    function windowInstance(moduleId, screenName) {
        windowRevision;
        return windowInstances[widgetKey(moduleId, screenName)] || null;
    }

    function parseScanOutput(text) {
        var lines = text.split("\n");
        var parsed = {};

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line)
                continue;

            var parts = line.split("|");
            if (parts.length < 5)
                continue;

            var id = parts[0];
            var hasWidget = parts[1] === "true";
            var hasPopup = parts[2] === "true";
            var hasService = parts[3] === "true";
            var basePath = parts[4];

            if (!id)
                continue;

            parsed[id] = {
                id: id,
                basePath: basePath,
                hasWidget: hasWidget,
                hasPopup: hasPopup,
                hasService: hasService
            };
        }

        packages = parsed;
        ready = true;
        packagesRevision += 1;
        loaded();
    }
}
