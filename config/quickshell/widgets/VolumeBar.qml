import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ═════════════════════════════════════════════════════════════════════
//   Volume bar verticale — bord gauche
//   - 30 segments qui morphent carré (vide) ↔ barre fine (rempli)
//   - Scroll / clic / drag
//   - Contrôle PulseAudio via pactl (compatible pavucontrol)
//   - Écran actif uniquement
//   - Click-through hors de la zone active : le panel lui-même change
//     de largeur et de hauteur pour ne couvrir que ce qui est utile.
// ═════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── Paramètres ──
    readonly property int segments: 30
    readonly property int hoverWidth: 65
    readonly property int barWidth: 40
    readonly property int barHeight: 420
    readonly property int leftOffset: 18
    readonly property int hideDelay: 400

    readonly property int segFilledW: 14
    readonly property int segEmptyW:  4
    readonly property int segEmptyH:  4
    readonly property int segFilledH: 3
    readonly property int segActiveW: 22
    readonly property int segActiveH: 5

    readonly property color colFilled: "#a89a7e"
    readonly property color colEmpty:  "#c8b89a"
    readonly property color colBg:     "#0f0d0a"

    // ── État volume ──
    property real volume: 0.5
    property bool muted: false
    property bool userInteracting: false

    // ── Écran actif ──
    property string activeMonitor: ""
    Timer {
        interval: 200; running: true; repeat: true
        onTriggered: activeMonitorProc.running = true
    }
    Process {
        id: activeMonitorProc
        command: ["sh","-c","hyprctl cursorpos -j | python3 -c \"\nimport sys,json,subprocess\npos=json.load(sys.stdin)\nmons=json.loads(subprocess.check_output(['hyprctl','monitors','-j']))\nfor m in mons:\n    x,y=m['x'],m['y']\n    w,h=m['width'],m['height']\n    if x<=pos['x']<x+w and y<=pos['y']<y+h:\n        print(m['name'])\n        break\n\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var n = this.text.trim()
                if (n !== "" && n !== root.activeMonitor) root.activeMonitor = n
            }
        }
    }

    // ── Poll volume ──
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: if (!root.userInteracting) getVolProc.running = true
    }
    Process {
        id: getVolProc
        command: ["sh","-c","pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\\d+(?=%)' | head -1; pactl get-sink-mute @DEFAULT_SINK@ | grep -oP '(yes|no)'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                if (lines.length >= 1) {
                    var v = parseInt(lines[0])
                    if (!isNaN(v)) root.volume = Math.max(0, Math.min(1, v / 100))
                }
                if (lines.length >= 2) root.muted = (lines[1] === "yes")
            }
        }
    }

    function setVolume(v) {
        v = Math.max(0, Math.min(1, v))
        root.volume = v
        var pct = Math.round(v * 100)
        setVolProc.command = ["pactl","set-sink-volume","@DEFAULT_SINK@", pct + "%"]
        setVolProc.running = true
    }
    Process { id: setVolProc; command: ["sh","-c","true"]; running: false }

    // ═══════════════════════════════════
    //   Un seul PanelWindow par écran
    //   - Hauteur FIXE : barHeight (plus zone label), centré verticalement
    //   - Largeur dynamique : hoverWidth quand caché, large quand révélé
    //   Tout ce qui est en dehors de cette zone est click-through natif
    //   (pas de panel = pas de capture d'events).
    // ═══════════════════════════════════
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors.left: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property bool isActive: modelData.name === root.activeMonitor

            // État révélé : hover sur une des zones ou interaction
            property bool revealed: hoverArea.containsMouse
                                  || barMouseArea.containsMouse
                                  || barMouseArea.pressed
                                  || hideTimer.running

            // Largeur : juste la zone de hover quand caché, étendue quand révélé
            // Hauteur : toujours celle de la barre (+ marge pour label)
            implicitWidth: revealed
                ? (root.leftOffset + root.barWidth + 10)
                : root.hoverWidth
            implicitHeight: root.barHeight + 40

            // Centré verticalement
            margins.top: (modelData.height - implicitHeight) / 2

            visible: isActive

            Timer {
                id: hideTimer
                interval: root.hideDelay
                repeat: false
            }

            // ── Zone de hover au bord (toujours active) ──
            MouseArea {
                id: hoverArea
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                x: 0
                y: 0
                width: root.hoverWidth
                height: parent.height
                onEntered: hideTimer.stop()
                onExited:  hideTimer.restart()
            }

            // ── La barre (apparaît à droite de la zone de hover) ──
            Item {
                id: barContainer
                width: root.barWidth
                height: root.barHeight
                anchors.verticalCenter: parent.verticalCenter
                x: panel.revealed ? root.leftOffset : -root.barWidth
                opacity: panel.revealed ? 1 : 0

                Behavior on x       { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 220 } }

                // Fond
                Rectangle {
                    anchors.fill: parent
                    color: root.colBg
                    opacity: 0.55
                    border.color: root.colFilled
                    border.width: 1
                }

                // Segments
                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2

                    Repeater {
                        model: root.segments
                        Item {
                            width: parent.width
                            height: (root.barHeight - 12 - (root.segments - 1) * 2) / root.segments

                            property real segLevel: 1 - (index / (root.segments - 1))
                            property bool filled: root.volume >= segLevel - 0.0001
                            property real segStep: 1 / (root.segments - 1)
                            property bool active: filled && (root.volume < segLevel + segStep - 0.0001)

                            Rectangle {
                                anchors.centerIn: parent
                                width:  parent.active ? root.segActiveW
                                      : parent.filled ? root.segFilledW
                                      :                 root.segEmptyW
                                height: parent.active ? root.segActiveH
                                      : parent.filled ? root.segFilledH
                                      :                 root.segEmptyH
                                radius: parent.filled ? 1 : 0
                                color: parent.filled
                                       ? (root.muted ? "#6e2a2a" : root.colFilled)
                                       : root.colEmpty

                                Behavior on width   { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on height  { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on color   { ColorAnimation  { duration: 220 } }
                                Behavior on radius  { NumberAnimation { duration: 220 } }
                            }
                        }
                    }
                }

                // MouseArea d'interaction : scroll / clic / drag
                MouseArea {
                    id: barMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton

                    function yToVolume(y) {
                        var m = 6
                        var h = height - 2 * m
                        return Math.max(0, Math.min(1, 1 - (y - m) / h))
                    }

                    onEntered: hideTimer.stop()
                    onExited:  hideTimer.restart()

                    onPressed: function(e) {
                        root.userInteracting = true
                        root.setVolume(yToVolume(e.y))
                    }
                    onReleased: root.userInteracting = false
                    onPositionChanged: function(e) {
                        if (pressed) root.setVolume(yToVolume(e.y))
                    }
                    onWheel: function(e) {
                        var step = 0.08
                        if (e.angleDelta.y > 0) root.setVolume(root.volume + step)
                        else                    root.setVolume(root.volume - step)
                        hideTimer.restart()
                    }
                }

                // Label % en haut
                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: -16
                    text: root.muted ? "MUTE" : Math.round(root.volume * 100) + "%"
                    font.family: "Share Tech Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    color: root.colFilled
                    opacity: 0.8
                }
            }
        }
    }
}
