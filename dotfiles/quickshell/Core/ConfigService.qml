pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Merge.js" as Merge

Scope {
    id: root

    property string shellConfigPath: Qt.resolvedUrl("../Config/shell.json").toString().replace("file://", "")
    property string privateConfigPath: Qt.resolvedUrl("../Config/private.json").toString().replace("file://", "")

    property var shellData: ({})
    property var privateData: ({})
    readonly property var data: Merge.deepMerge(shellData, privateData)

    signal reloaded()

    function parseJson(text, label) {
        if (!text || text.trim() === "")
            return {};

        try {
            return JSON.parse(text);
        } catch (error) {
            console.warn("ConfigService:", label, "parse error:", error);
            return {};
        }
    }

    function reloadAll() {
        shellData = parseJson(shellFile.text(), "shell.json");
        privateData = parseJson(privateFile.text(), "private.json");
        reloaded();
    }

    function section(name, defaults) {
        return Merge.deepMerge(defaults || {}, data[name] || {});
    }

    function privateSection(name) {
        return Merge.deepMerge({}, privateData[name] || {});
    }

    function packageConfig(id, defaults) {
        var result = Merge.deepMerge(defaults || {}, data[id] || {});
        var modules = data.modules || {};
        return Merge.deepMerge(result, modules[id] || {});
    }

    function packagePrivateConfig(id) {
        var result = Merge.deepMerge({}, privateData[id] || {});
        var modules = privateData.modules || {};
        return Merge.deepMerge(result, modules[id] || {});
    }

    function isPackageEnabled(id, defaults) {
        return packageConfig(id, defaults || {}).enabled !== false;
    }

    FileView {
        id: shellFile
        path: root.shellConfigPath
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.reloadAll();
        }
    }

    FileView {
        id: privateFile
        path: root.privateConfigPath
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.reloadAll();
        }
    }

    Component.onCompleted: root.reloadAll()
}
