import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Draws a thin red frame around a screen region while recording.
//
// Handoff: bin/screen-record writes a slurp geometry string ("X,Y WxH") to
// /tmp/recordborder.geom and calls `qs ipc call recordborder start` (zero-arg);
// `hide` clears it. We read the file via a one-shot Process and flip `active`.
//
// IMPORTANT — two bugs were fixed here:
//  1. The IPC function used to be named `show`. The Quickshell 0.3.0
//     `qs ipc call <target> show` CLI treats the literal word `show` as a
//     reserved keyword (like `qs ipc show`) and prints the handler listing
//     instead of invoking the function — so the border never appeared even
//     though rc=0. Renamed to `start` (any non-reserved name works).
//  2. An EMPTY `mask: Region {}` made the wlr layer-surface commit at 0x0,
//     so the overlay had no size to render into. Fixed with a non-empty
//     `Region { item: ... }` (the NotificationPopup idiom): it gives the
//     surface a real size and limits the input region to the frame, so
//     clicks outside the recorded region still pass through to windows below.
Item {
	id: root

	property bool active: false
	property int regX: 0
	property int regY: 0
	property int regW: 0
	property int regH: 0
	property int thickness: 3

	function applyGeom(text) {
		const t = (text || "").trim();
		const m = t.match(/^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$/);
		if (!m) {
			console.log("recordborder: geom parse FAILED for:", JSON.stringify(t));
			return;
		}
		root.regX = parseInt(m[1]);
		root.regY = parseInt(m[2]);
		root.regW = parseInt(m[3]);
		root.regH = parseInt(m[4]);
		root.active = true;
		console.log("recordborder: active=true geom=", root.regX, root.regY, root.regW, root.regH);
	}

	Process {
		id: geomProc
		command: ["cat", "/tmp/recordborder.geom"]
		running: false
		stdout: StdioCollector {
			id: geomCollector
			waitForEnd: true
			onStreamFinished: root.applyGeom(geomCollector.text)
		}
	}

	IpcHandler {
		target: "recordborder"

		// NB: do NOT name this `show` — the qs CLI reserves that word and will
		// print the handler listing instead of calling the function.
		function start(): void {
			console.log("recordborder: start() called");
			geomProc.running = true;
		}

		function hide(): void {
			console.log("recordborder: hide() called");
			root.active = false;
		}
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: win
			required property var modelData
			screen: modelData

			color: "transparent"
			exclusionMode: ExclusionMode.Ignore
			visible: root.active

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "quickshell-recordborder"
			WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

			anchors {
				top: true
				bottom: true
				left: true
				right: true
			}

			implicitWidth: modelData.width
			implicitHeight: modelData.height

			// Border position in this window's local coordinates.
			readonly property int bx: root.regX - modelData.x
			readonly property int by: root.regY - modelData.y
			readonly property int bw: root.regW
			readonly property int bh: root.regH
			readonly property int th: root.thickness

			// Input region = the frame's bounding box only -> click-through
			// outside the recorded region, and a non-zero surface size so the
			// frame actually renders.
			mask: Region { item: frame }

			Item {
				id: frame
				x: win.bx - win.th
				y: win.by - win.th
				width: win.bw + win.th * 2
				height: win.bh + win.th * 2

				Rectangle { // top
					color: "#ff3b30"
					anchors { top: parent.top; left: parent.left; right: parent.right }
					height: win.th
				}
				Rectangle { // bottom
					color: "#ff3b30"
					anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
					height: win.th
				}
				Rectangle { // left
					color: "#ff3b30"
					anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
					width: win.th
				}
				Rectangle { // right
					color: "#ff3b30"
					anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
					width: win.th
				}
			}
		}
	}
}
