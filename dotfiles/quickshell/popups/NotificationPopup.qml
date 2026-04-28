import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    property string position: AppConfig.Config.notifications.position
    property int horizontalOffset: AppConfig.Config.notifications.horizontalOffset
    property int maxEntries: AppConfig.Config.notifications.maxEntries
    property int maxVisible: AppConfig.Config.notifications.maxVisible

    // --- Theme: Colors ---
    property color defaultBg: AppConfig.Config.notifications.defaultBg
    property color defaultFg: AppConfig.Config.notifications.defaultFg
    property color dimText: AppConfig.Config.notifications.dimText
    property color mutedText: AppConfig.Config.notifications.mutedText
    property color trackBg: AppConfig.Config.notifications.trackBg
    property color timeoutBar: AppConfig.Config.notifications.timeoutBar
    property real timeoutBarOpacity: AppConfig.Config.notifications.timeoutBarOpacity

    // --- Theme: Typography ---
    property string fontFamily: AppConfig.Config.notifications.fontFamily
    property int fontSizeTitle: AppConfig.Config.notifications.fontSizeTitle
    property int fontSizeBody: AppConfig.Config.notifications.fontSizeBody
    property int fontSizeSmall: AppConfig.Config.notifications.fontSizeSmall
    property int fontSizeMeta: AppConfig.Config.notifications.fontSizeMeta

    // --- Theme: Layout ---
    property int iconSize: AppConfig.Config.notifications.iconSize
    property int cardPadding: AppConfig.Config.notifications.cardPadding
    property int cardRadius: AppConfig.Config.notifications.cardRadius
    property int cardSpacing: AppConfig.Config.notifications.cardSpacing
    property int actionHeight: AppConfig.Config.notifications.actionHeight
    property int actionRadius: AppConfig.Config.notifications.actionRadius

    // --- Theme: Animation ---
    property int animEnter: AppConfig.Config.notifications.animEnter
    property int animExit: AppConfig.Config.notifications.animExit
    property int animSlideOffset: AppConfig.Config.notifications.animSlideOffset

    // Exposed for Bar.qml notification icon
    property int activeCount: visibleCount
    property bool dnd: false

    anchors {
        top: position.indexOf("top") !== -1
        bottom: position.indexOf("bottom") !== -1
        left: position.indexOf("left") !== -1
        right: position.indexOf("right") !== -1
    }

    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight + AppConfig.Config.theme.spacingSmall
    margins.right: AppConfig.Config.theme.spacingDefault
    margins.left: screen ? (screen.width - implicitWidth) / 2 + horizontalOffset : horizontalOffset
    margins.bottom: AppConfig.Config.theme.spacingDefault
    implicitWidth: 400
    implicitHeight: screen ? screen.height - barHeight - 12 : 1400
    visible: true
    color: "transparent"

    mask: Region {
        item: notifColumn
    }

    property bool debug: false
    function dbg(msg) {
        if (!debug) return;
        logProc.command = ["sh", "-c", "echo '" + msg.replace(/'/g, "'\\''") + "' >> /tmp/qs-notif.log"];
        logProc.running = true;
    }
    Process { id: logProc; running: false }

    IpcHandler {
        target: "notif"
        function close(): void { root.dismissLatest(); }
        function closeAll(): void { root.dismissAll(); }
        function historyPop(): void { root.historyPop(); }
        function context(): void { root.invokeLatest(); }
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        keepOnReload: true

        onNotification: notif => {
            dbg("[notif] onNotification id=" + notif.id + " summary=" + notif.summary);
            notif.tracked = true;
            addNotification(notif);
        }
    }

    // --- Notification stack (max 40 total, 20 visible, arrival order) ---
    // Single list: items stay in place. Expire/dismiss = hide + server dismiss. Pop = unhide.
    ListModel {
        id: visibleModel
    }

    property var notifRefs: ({})  // QObject refs keyed by nid
    property int nextNid: 1
    property int visibleCount: 0  // track non-hidden items for window visibility
    property double clockTick: Date.now()  // updated every 30s for time-ago display

    property var rulesConfig: ({rules: [], defaults: {}})
    property var regexCache: ({})

    FileView {
        id: rulesFile
        path: Qt.resolvedUrl("notif-rules.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: { this.reload(); root.loadRules(); }
        Component.onCompleted: root.loadRules()
    }

    // Convert #RRGGBBAA → #AARRGGBB (QML format)
    function toQmlColor(c) {
        if (typeof c === "string" && c.length === 9 && c[0] === "#")
            return "#" + c.slice(7, 9) + c.slice(1, 7);
        return c;
    }

    function fixColors(obj) {
        if (obj.bg) obj.bg = toQmlColor(obj.bg);
        if (obj.fg) obj.fg = toQmlColor(obj.fg);
    }

    function loadRules() {
        try {
            var cfg = JSON.parse(rulesFile.text());
            if (cfg.rules && cfg.defaults) {
                for (var i = 0; i < cfg.rules.length; i++) fixColors(cfg.rules[i]);
                var keys = Object.keys(cfg.defaults);
                for (var j = 0; j < keys.length; j++) fixColors(cfg.defaults[keys[j]]);
                rulesConfig = cfg;
                regexCache = {};
            }
        } catch(e) {
            dbg("[notif] Failed to parse notif-rules.json: " + e);
        }
    }

    function matchField(pattern, value) {
        if (typeof pattern !== "string") return false;
        var m = pattern.match(/^\/(.+)\/([i]?)$/);
        if (m) {
            var key = pattern;
            if (!regexCache[key]) regexCache[key] = new RegExp(m[1], m[2]);
            return regexCache[key].test(value || "");
        }
        return pattern === value;
    }

    function resolveStyle(summary, body, appName, urgency) {
        var urgencyKey = urgency === NotificationUrgency.Low ? "low"
                       : urgency === NotificationUrgency.Critical ? "critical" : "normal";
        var base = rulesConfig.defaults[urgencyKey] || {};
        var style = {
            bg: base.bg || root.defaultBg, fg: base.fg || root.defaultFg,
            timeout: base.timeout !== undefined ? base.timeout : 10000,
            hideHeader: false, hideActions: false,
            maxLines: 4, boldBody: false, bodySize: root.fontSizeBody
        };
        var rules = rulesConfig.rules;
        for (var i = 0; i < rules.length; i++) {
            var rule = rules[i];
            var match = rule.match;
            if (!match) continue;
            var ok = true;
            if (match.appName !== undefined && !matchField(match.appName, appName)) ok = false;
            if (ok && match.summary !== undefined && !matchField(match.summary, summary)) ok = false;
            if (ok && match.body !== undefined && !matchField(match.body, body)) ok = false;
            if (ok && match.urgency !== undefined && !matchField(match.urgency, urgencyKey)) ok = false;
            if (ok) {
                if (rule.bg !== undefined) style.bg = rule.bg;
                if (rule.fg !== undefined) style.fg = rule.fg;
                if (rule.timeout !== undefined) style.timeout = rule.timeout;
                if (rule.hideHeader !== undefined) style.hideHeader = rule.hideHeader;
                if (rule.hideActions !== undefined) style.hideActions = rule.hideActions;
                if (rule.maxLines !== undefined) style.maxLines = rule.maxLines;
                if (rule.boldBody !== undefined) style.boldBody = rule.boldBody;
                if (rule.bodySize !== undefined) style.bodySize = rule.bodySize;
                break;
            }
        }
        return style;
    }

    function getHintValue(obj) {
        try { if (obj.hints && obj.hints.value !== undefined) return obj.hints.value; } catch(e) {}
        return -1;
    }

    function timeAgo(arrivedAt) {
        var mins = Math.floor((Date.now() - arrivedAt) / 60000);
        if (mins < 1) return "";
        if (mins < 60) return mins + "m";
        var h = Math.floor(mins / 60);
        var m = mins % 60;
        return m > 0 ? h + "h" + m + "m" : h + "h";
    }

    // Called when quickshell updates a notification QObject in-place (replacement).
    // onNotification does NOT fire for replacements — only property change signals do.
    function connectNotifSignals(notif, nid) {
        var update = function() { updateModelFromRef(nid); };
        notif.summaryChanged.connect(update);
        notif.bodyChanged.connect(update);
        notif.hintsChanged.connect(update);
    }

    function makeEntry(nid, realId, notif, tag, arrivedAt, hidden) {
        var s = resolveStyle(notif.summary || "", notif.body || "", notif.appName || "", notif.urgency);
        var t = notif.expireTimeout >= 0 ? notif.expireTimeout : s.timeout;
        return {
            nid: nid,
            realId: realId,
            summary: notif.summary || "",
            body: notif.body || "",
            appName: notif.appName || "",
            appIcon: notif.appIcon || "",
            image: notif.image || "",
            urgency: notif.urgency,
            hintValue: getHintValue(notif),
            hasActions: notif.actions && notif.actions.length > 0,
            isHistory: false,
            hidden: hidden,
            dismissed: false,
            tag: tag,
            arrivedAt: arrivedAt,
            timeout: t,
            paused: false,
            elapsed: 0
        };
    }

    function updateModelFromRef(nid) {
        var ref = notifRefs[nid];
        dbg("[notif] updateModelFromRef nid=" + nid + " hasRef=" + !!ref);
        if (!ref) return;
        for (var i = 0; i < visibleModel.count; i++) {
            var e = visibleModel.get(i);
            if (e.nid !== nid) continue;
            var wasHidden = e.hidden;
            visibleModel.set(i, makeEntry(nid, e.realId, ref, e.tag, e.arrivedAt, false));
            if (wasHidden) visibleCount++;
            return;
        }
    }

    function getTag(notif) {
        try {
            var h = notif.hints;
            if (h && h["x-tag"]) {
                var v = h["x-tag"];
                if (typeof v === "string") return v;
                if (v && v.data) return v.data;
                return String(v);
            }
        } catch(e) {}
        return "";
    }

    function addNotification(notif) {
        var tag = getTag(notif);
        dbg("[notif] add id=" + notif.id + " tag=" + tag + " count=" + visibleModel.count);
        // Check for existing entry with same realId or tag (replacement)
        for (var i = 0; i < visibleModel.count; i++) {
            var existing = visibleModel.get(i);
            var match = existing.realId === notif.id || (tag !== "" && existing.tag === tag);
            if (match) {
                dbg("[notif]   REPLACE i=" + i + " realId=" + existing.realId + " tag=" + existing.tag);
                var wasHidden = existing.hidden;
                var isDnd = root.dnd;
                notifRefs[existing.nid] = notif;
                visibleModel.set(i, makeEntry(existing.nid, notif.id, notif, tag, existing.arrivedAt, isDnd));
                connectNotifSignals(notif, existing.nid);
                if (wasHidden && !isDnd) visibleCount++;
                return;
            }
        }

        // Cap total entries — evict oldest hidden first, then force-evict oldest
        while (visibleModel.count >= maxEntries) {
            var found = false;
            for (var k = visibleModel.count - 1; k >= 0; k--) {
                if (visibleModel.get(k).hidden) {
                    evictEntry(k);
                    found = true;
                    break;
                }
            }
            if (!found) evictEntry(visibleModel.count - 1);
        }

        var nid = nextNid++;
        dbg("[notif]   NEW nid=" + nid + " id=" + notif.id + " tag=" + tag);
        var isDnd = root.dnd;
        notifRefs[nid] = notif;
        visibleModel.insert(0, makeEntry(nid, notif.id, notif, tag, Date.now(), isDnd));
        connectNotifSignals(notif, nid);
        if (!isDnd) visibleCount++;
    }

    function historyPop() {
        if (visibleCount >= maxVisible) return;
        for (var i = 0; i < visibleModel.count; i++) {
            if (!visibleModel.get(i).hidden) continue;
            visibleModel.setProperty(i, "hidden", false);
            visibleModel.setProperty(i, "isHistory", true);
            visibleModel.setProperty(i, "timeout", 0);
            visibleModel.setProperty(i, "elapsed", 0);
            visibleModel.setProperty(i, "paused", false);
            visibleModel.setProperty(i, "hasActions", false);
            visibleCount++;
            return;
        }
    }

    function releaseRef(nid) {
        var ref = notifRefs[nid];
        if (ref && typeof ref.dismiss === "function") ref.dismiss();
        delete notifRefs[nid];
    }

    function invokeDefaultAction(nid) {
        var ref = notifRefs[nid];
        if (ref && ref.actions && ref.actions.length > 0 && typeof ref.actions[0].invoke === "function")
            ref.actions[0].invoke();
    }

    function hideEntry(idx) {
        if (idx < 0 || idx >= visibleModel.count) return;
        var e = visibleModel.get(idx);
        if (e.hidden) return;
        visibleModel.setProperty(idx, "hidden", true);
        visibleModel.setProperty(idx, "dismissed", true);
        releaseRef(e.nid);
        visibleCount--;
    }

    function evictEntry(idx) {
        var e = visibleModel.get(idx);
        if (!e.dismissed) releaseRef(e.nid);
        if (!e.hidden) visibleCount--;
        visibleModel.remove(idx);
    }

    function animateHide(idx) {
        if (idx < 0 || idx >= visibleModel.count) return;
        var item = notifRepeater.itemAt(idx);
        if (item && !item.dismissing) item.animateDismiss();
        else hideEntry(idx);
    }

    function dismissLatest() {
        for (var i = visibleModel.count - 1; i >= 0; i--) {
            if (!visibleModel.get(i).hidden) {
                animateHide(i);
                return;
            }
        }
    }

    function dismissAll() {
        for (var i = 0; i < visibleModel.count; i++) {
            var e = visibleModel.get(i);
            if (e.hidden) continue;
            visibleModel.setProperty(i, "hidden", true);
            visibleModel.setProperty(i, "dismissed", true);
            releaseRef(e.nid);
        }
        visibleCount = 0;
    }

    function invokeLatest() {
        for (var i = 0; i < visibleModel.count; i++) {
            var e = visibleModel.get(i);
            if (e.hidden) continue;
            invokeDefaultAction(e.nid);
            animateHide(i);
            return;
        }
    }

    Timer {
        id: tickTimer
        interval: 100
        running: visibleCount > 0
        repeat: true
        onTriggered: {
            for (var i = 0; i < visibleModel.count; i++) {
                var entry = visibleModel.get(i);
                if (entry.hidden || entry.paused || entry.timeout <= 0) continue;
                var newElapsed = entry.elapsed + 100;
                if (newElapsed >= entry.timeout) {
                    animateHide(i);
                } else {
                    visibleModel.setProperty(i, "elapsed", newElapsed);
                }
            }
        }
    }

    Timer {
        interval: 30000
        running: visibleCount > 0
        repeat: true
        onTriggered: root.clockTick = Date.now()
    }

    Column {
        id: notifColumn
        width: parent.width
        spacing: root.cardSpacing

        Repeater {
            id: notifRepeater
            model: visibleModel

            Item {
                id: cardWrapper
                width: notifColumn.width
                height: hidden ? 0 : card.height
                visible: !hidden
                opacity: 0

                required property int index
                required property int nid
                required property string summary
                required property string body
                required property string appName
                required property string appIcon
                required property string image
                required property int urgency
                required property int hintValue
                required property bool hasActions
                required property bool isHistory
                required property bool hidden
                required property bool dismissed
                required property string tag
                required property double arrivedAt
                required property int timeout
                required property bool paused
                required property int elapsed

                property var notifStyle: root.resolveStyle(summary, body, appName, urgency)

                Component.onCompleted: {
                    if (!hidden) cardEnter.start();
                }

                property bool dismissing: false

                onHiddenChanged: {
                    if (!hidden) {
                        dismissing = false;
                        opacity = 0;
                        cardEnter.start();
                    }
                }

                function animateDismiss() {
                    dismissing = true;
                    cardExit.start();
                }

                ParallelAnimation {
                    id: cardEnter
                    NumberAnimation { target: cardWrapper; property: "opacity"; from: 0; to: 1; duration: root.animEnter; easing.type: Easing.OutCubic }
                    NumberAnimation { target: card; property: "y"; from: -root.animSlideOffset; to: 0; duration: root.animEnter; easing.type: Easing.OutCubic }
                }

                ParallelAnimation {
                    id: cardExit
                    NumberAnimation { target: cardWrapper; property: "opacity"; from: 1; to: 0; duration: root.animExit; easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "y"; from: 0; to: -root.animSlideOffset; duration: root.animExit; easing.type: Easing.InCubic }
                    onFinished: root.hideEntry(cardWrapper.index)
                }

                Rectangle {
                    id: card
                    width: parent.width
                    height: cardContent.implicitHeight + root.cardPadding * 2 + (valueBar.visible ? 14 : 0) + (progressBar.visible ? 3 : 0)
                    radius: root.cardRadius
                    color: cardWrapper.notifStyle.bg
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onEntered: {
                            if (cardWrapper.index >= 0 && cardWrapper.index < visibleModel.count)
                                visibleModel.setProperty(cardWrapper.index, "paused", true);
                        }
                        onExited: {
                            if (cardWrapper.index >= 0 && cardWrapper.index < visibleModel.count)
                                visibleModel.setProperty(cardWrapper.index, "paused", false);
                        }
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.dismissAll();
                            } else {
                                if (!cardWrapper.dismissed)
                                    root.invokeDefaultAction(cardWrapper.nid);
                                root.animateHide(cardWrapper.index);
                            }
                        }
                    }

                    Column {
                        id: cardContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: root.cardPadding
                        spacing: AppConfig.Config.theme.spacingCompact

                        Row {
                            width: parent.width
                            spacing: AppConfig.Config.theme.spacingDefault
                            visible: !cardWrapper.notifStyle.hideHeader

                            Image {
                                id: notifIcon
                                width: root.iconSize
                                height: root.iconSize
                                anchors.verticalCenter: parent.verticalCenter
                                sourceSize.width: root.iconSize
                                sourceSize.height: root.iconSize
                                visible: status === Image.Ready
                                source: {
                                    if (cardWrapper.image !== "") return cardWrapper.image;
                                    if (cardWrapper.appIcon !== "") return Quickshell.iconPath(cardWrapper.appIcon, true) ?? "";
                                    if (cardWrapper.appName !== "") return Quickshell.iconPath(cardWrapper.appName.toLowerCase(), true) ?? "";
                                    return "";
                                }
                            }

                            Column {
                                width: parent.width - (notifIcon.visible ? 40 : 0)
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    width: parent.width
                                    spacing: AppConfig.Config.theme.spacingMedium

                                    Text {
                                        text: cardWrapper.summary
                                        color: cardWrapper.notifStyle.fg
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSizeTitle
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width - appNameLabel.implicitWidth - historyIcon.implicitWidth - agoLabel.implicitWidth - 18
                                    }

                                    Text {
                                        id: historyIcon
                                        text: "◷"
                                        visible: cardWrapper.dismissed
                                        color: root.dimText
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSizeMeta
                                        anchors.baseline: parent.children[0] ? parent.children[0].baseline : undefined
                                    }

                                    Text {
                                        id: agoLabel
                                        property string ago: { root.clockTick; return root.timeAgo(cardWrapper.arrivedAt); }
                                        text: ago
                                        visible: ago !== ""
                                        color: root.dimText
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSizeSmall
                                        anchors.baseline: parent.children[0] ? parent.children[0].baseline : undefined
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: cardWrapper.body
                                    color: cardWrapper.notifStyle.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: cardWrapper.notifStyle.bodySize
                                    font.bold: cardWrapper.notifStyle.boldBody
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: cardWrapper.notifStyle.maxLines
                                    elide: Text.ElideRight
                                    textFormat: cardWrapper.appName === "llm" ? Text.MarkdownText : Text.RichText
                                    visible: text !== ""
                                }
                            }
                        }

                        // Body-only mode (when header is hidden)
                        Text {
                            width: parent.width
                            text: cardWrapper.body
                            color: cardWrapper.notifStyle.fg
                            font.family: root.fontFamily
                            font.pixelSize: cardWrapper.notifStyle.bodySize
                            font.bold: cardWrapper.notifStyle.boldBody
                            wrapMode: Text.WordWrap
                            maximumLineCount: cardWrapper.notifStyle.maxLines
                            elide: Text.ElideRight
                            textFormat: cardWrapper.appName === "llm" ? Text.MarkdownText : Text.RichText
                            visible: cardWrapper.notifStyle.hideHeader && text !== ""
                        }

                        Item { width: 1; height: 4; visible: cardWrapper.hasActions && !cardWrapper.notifStyle.hideActions }

                        Row {
                            spacing: AppConfig.Config.theme.spacingCompact
                            width: parent.width
                            visible: cardWrapper.hasActions && !cardWrapper.notifStyle.hideActions
                            Repeater {
                                id: actionsRepeater
                                model: {
                                    var ref = root.notifRefs[cardWrapper.nid];
                                    return (ref && ref.actions) ? ref.actions : [];
                                }

                                Rectangle {
                                    required property var modelData
                                    width: (parent.width - (actionsRepeater.count - 1) * 2) / actionsRepeater.count
                                    height: root.actionHeight
                                    radius: root.actionRadius
                                    color: actionHover.hovered ? Helpers.Colors.accent : "transparent"
                                    border.color: Helpers.Colors.accent
                                    border.width: 1

                                    HoverHandler { id: actionHover }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        color: actionHover.hovered ? "white" : Helpers.Colors.accent
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSizeSmall
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.invoke();
                                            root.animateHide(cardWrapper.index);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: appNameLabel
                        text: cardWrapper.appName
                        color: root.mutedText
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSizeSmall
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        visible: !cardWrapper.notifStyle.hideHeader && cardWrapper.appName !== ""
                    }

                    Rectangle {
                        id: valueBar
                        anchors.bottom: progressBar.visible ? progressBar.top : parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.bottomMargin: progressBar.visible ? 4 : 6
                        height: 4
                        radius: 2
                        color: root.trackBg
                        visible: cardWrapper.hintValue >= 0

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, cardWrapper.hintValue / 100))
                            height: parent.height
                            radius: 2
                            color: Helpers.Colors.accent

                            Behavior on width {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Rectangle {
                        id: progressBar
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        height: 3
                        radius: 0
                        color: root.timeoutBar
                        opacity: root.timeoutBarOpacity
                        visible: cardWrapper.timeout > 0
                        width: cardWrapper.timeout > 0 ? parent.width * (1 - cardWrapper.elapsed / cardWrapper.timeout) : 0

                        Behavior on width {
                            NumberAnimation { duration: 100 }
                        }
                    }
                }
            }
        }
    }
}
