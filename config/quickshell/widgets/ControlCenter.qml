import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ═════════════════════════════════════════════════════════════════════
//   NieR Control Center — Quickshell module
//   Portage 1:1 du mockup HTML v4
//   Asset requis : ~/.config/quickshell/assets/nier-arrow.png
//   IPC : qs ipc call ctrl toggle
// ═════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── Paths ──
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string assetsDir:     xdgConfigHome + "/quickshell/assets"
    property string arrowPng:      "file://" + assetsDir + "/nier-arrow.png"

    // ── Palette NieR ──
    readonly property color colCard:     "#e8e0c8"
    readonly property color colCardSoft: Qt.rgba(232/255, 224/255, 200/255, 0.4)
    readonly property color colInk:      "#3a342a"
    readonly property color colInkSoft:  "#6a604a"
    readonly property color colHi:       "#1f1c16"
    readonly property color colLight:    "#f5edd5"

    // ── Layout ──
    readonly property int  slotGapV: 200
    readonly property int  slotGapH: 400
    readonly property int  panShiftV: 320   // vertical (top/bottom) : centre l'ensemble sub+settings
    readonly property int  panShiftH: 700   // horizontal (left/right) : laisse la place pour la flèche

    // ── État ──
    property bool   open:    false
    property bool   closing: false   // état intermédiaire : slots reviennent au centre, puis fade
    property int    level:   1
    property string slot:    "center"
    property string sub:     ""
    property string action:  ""

    // ── Données ──
    readonly property var subs: ({
        top:    [ {key:"wifi",      label:"Wi-Fi"},
                  {key:"bluetooth", label:"Bluetooth"} ],
        bottom: [ {key:"output",    label:"Output"},
                  {key:"volume",    label:"Volume"} ],
        left:   [ {key:"send",      label:"Send"},
                  {key:"receive",   label:"Receive"} ],
        right:  [ {key:"history",   label:"History"},
                  {key:"dnd",       label:"Do Not Disturb"} ]
    })

    readonly property var details: ({
        "top.wifi":         {h3:"Wi-Fi",               status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Wi-Fi"}]},
        "top.bluetooth":    {h3:"Bluetooth",           status:"—",    on:false,
                              actions:[{key:"toggle",label:"Toggle Bluetooth"}]},
        "bottom.output":    {h3:"Audio Output",        status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "bottom.volume":    {h3:"Volume",              status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "left.send":        {h3:"Send Files",          status:"Ready", on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "left.receive":     {h3:"Receive Files",       status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.history":    {h3:"Notification History",status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]},
        "right.dnd":        {h3:"Do Not Disturb",      status:"—",    on:false,
                              actions:[{key:"placeholder",label:"Sub-menu coming"}]}
    })

    function detailKey() { return slot + "." + sub }
    function subList(s)  { return root.subs[s] || [] }

    // ── Construit la liste d'actions dynamique selon le sub focus ──
    function actList() {
        var key = detailKey()
        // Wi-Fi : toggle + un bouton par réseau scanné
        if (key === "top.wifi") {
            var acts = [{key:"toggle", label: wifiEnabled ? "Disable Wi-Fi" : "Enable Wi-Fi"}]
            if (wifiEnabled) {
                for (var i = 0; i < wifiNetworks.length; i++) {
                    var n = wifiNetworks[i]
                    var prefix = n.active ? "✓ " : "  "
                    var sigBars = n.signal >= 75 ? "▰▰▰" : n.signal >= 50 ? "▰▰▱" : n.signal >= 25 ? "▰▱▱" : "▱▱▱"
                    acts.push({
                        key: "connect:" + n.ssid,
                        label: prefix + n.ssid + "  " + sigBars
                    })
                }
            }
            return acts
        }
        // Bluetooth : toggle + un bouton par device paired
        if (key === "top.bluetooth") {
            var acts2 = [{key:"toggle", label: btEnabled ? "Disable Bluetooth" : "Enable Bluetooth"}]
            if (btEnabled) {
                for (var j = 0; j < btDevices.length; j++) {
                    var d = btDevices[j]
                    var label = (d.connected ? "✓ " : "  ") + d.name
                    var aKey = (d.connected ? "disconnect:" : "connect:") + d.mac
                    acts2.push({key: aKey, label: label})
                }
            }
            return acts2
        }
        // Autres : actions statiques du dictionnaire details
        var d = root.details[key]
        return d ? d.actions : []
    }

    // ── h3/status dynamique pour Wi-Fi/BT ──
    function detailH3() {
        var key = detailKey()
        if (key === "top.wifi")      return "Wi-Fi"
        if (key === "top.bluetooth") return "Bluetooth"
        var d = root.details[key]
        return d ? d.h3 : ""
    }
    function detailStatus() {
        var key = detailKey()
        if (key === "top.wifi") {
            if (!wifiEnabled) return "Disabled"
            if (wifiCurrentSSID) return "Connected · " + wifiCurrentSSID
            return "Enabled · Scanning"
        }
        if (key === "top.bluetooth") {
            if (!btEnabled) return "Disabled"
            var connected = btDevices.filter(function(d){return d.connected})
            if (connected.length) return "Connected · " + connected[0].name
            return "Enabled · " + btDevices.length + " paired"
        }
        var d = root.details[key]
        return d ? d.status : ""
    }
    function detailOn() {
        var key = detailKey()
        if (key === "top.wifi")      return wifiEnabled
        if (key === "top.bluetooth") return btEnabled
        var d = root.details[key]
        return d ? d.on : false
    }
    // ── Données système : Wi-Fi ──
    property bool   wifiEnabled: false
    property string wifiCurrentSSID: ""
    property var    wifiNetworks: []   // [{ssid, signal, security, active}]

    Timer {
        interval: 3000; running: root.open && root.slot === "top"; repeat: true; triggeredOnStart: true
        onTriggered: pollWifi.running = true
    }
    Process {
        id: pollWifi
        // Récupère état radio + liste des réseaux scannés
        command: ["sh","-c",
            "echo \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null | head -20"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                root.wifiEnabled = (lines[0] || "").trim() === "enabled"
                var nets = []
                var current = ""
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split(":")
                    if (parts.length < 4) continue
                    var inUse = parts[0] === "*"
                    var ssid = parts[1]
                    var signal = parseInt(parts[2]) || 0
                    var security = parts[3] || "Open"
                    if (!ssid) continue
                    if (inUse) current = ssid
                    nets.push({ssid: ssid, signal: signal, security: security, active: inUse})
                }
                root.wifiNetworks = nets
                root.wifiCurrentSSID = current
            }
        }
    }

    // ── Données système : Bluetooth ──
    property bool   btEnabled: false
    property var    btDevices: []   // [{name, mac, connected, paired}]

    Timer {
        interval: 3000; running: root.open && root.slot === "top"; repeat: true; triggeredOnStart: true
        onTriggered: pollBt.running = true
    }
    Process {
        id: pollBt
        // Récupère powered + liste des appareils paired (avec leur état connected)
        command: ["sh","-c",
            "echo \"$(bluetoothctl show 2>/dev/null | grep -i 'powered:' | awk '{print $2}')\"; " +
            "bluetoothctl devices Paired 2>/dev/null | while read line; do " +
            "  mac=$(echo $line | awk '{print $2}'); " +
            "  name=$(echo $line | cut -d' ' -f3-); " +
            "  conn=$(bluetoothctl info $mac 2>/dev/null | grep -i 'Connected:' | awk '{print $2}'); " +
            "  echo \"$mac|$name|$conn\"; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                root.btEnabled = (lines[0] || "").trim() === "yes"
                var devices = []
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length < 3) continue
                    devices.push({
                        mac: parts[0],
                        name: parts[1] || parts[0],
                        connected: (parts[2] || "").trim() === "yes"
                    })
                }
                root.btDevices = devices
            }
        }
    }

    // ── Process pour exécuter les actions ──
    Process { id: actProc; command: ["sh","-c","true"]; running: false }

    function firstSub(s) { var l = subList(s); return l.length ? l[0].key : "" }
    function firstAction() { var l = actList(); return l.length ? l[0].key : "" }

    // ── Dispatcher des actions de boutons ──
    function dispatchAction(slotKey, subKey, actionKey) {
        console.log("[ControlCenter] action:", slotKey + "." + subKey + "." + actionKey)
        var cmd = ""

        // ── Wi-Fi ──
        if (slotKey === "top" && subKey === "wifi") {
            if (actionKey === "toggle") {
                cmd = "nmcli radio wifi " + (wifiEnabled ? "off" : "on")
            } else if (actionKey.indexOf("connect:") === 0) {
                var ssid = actionKey.substring(8)
                cmd = "nmcli dev wifi connect '" + ssid + "' || nm-connection-editor &"
            }
        }
        // ── Bluetooth ──
        else if (slotKey === "top" && subKey === "bluetooth") {
            if (actionKey === "toggle") {
                cmd = "bluetoothctl power " + (btEnabled ? "off" : "on")
            } else if (actionKey.indexOf("connect:") === 0) {
                var mac = actionKey.substring(8)
                cmd = "bluetoothctl connect " + mac
            } else if (actionKey.indexOf("disconnect:") === 0) {
                var mac2 = actionKey.substring(11)
                cmd = "bluetoothctl disconnect " + mac2
            }
        }

        if (cmd) {
            actProc.command = ["sh","-c", cmd]
            actProc.running = true
            // refresh state après une seconde
            refreshTimer.restart()
        }
    }
    Timer {
        id: refreshTimer
        interval: 800; repeat: false
        onTriggered: { pollWifi.running = true; pollBt.running = true }
    }

    function activateCurrent() {
        if (level === 3 && action) {
            dispatchAction(slot, sub, action)
        }
    }

    // ── Toggle / IPC ──
    function toggle() {
        if (open || closing) close()
        else {
            open = true; closing = false
            level = 1; slot = "center"; sub = ""; action = ""
        }
    }
    function close() {
        if (!open) return
        // Phase 1 : on remet level à 1 (slot=center) et on déclenche closing.
        // Les slots reviennent au centre, le centre reste visible.
        level = 1; slot = "center"; sub = ""; action = ""
        closing = true
        closeTimer.start()
    }
    function back()  {
        if (level === 3) { level = 1; sub = ""; action = ""; slot = "center" }
        else close()
    }

    // Timer qui finalise la fermeture après que les slots soient revenus au centre
    Timer {
        id: closeTimer
        interval: 600  // attendre la fin de l'animation des slots (560ms + marge)
        repeat: false
        onTriggered: {
            // Phase 2 : on cache vraiment (fade out via opacity 0 dans le panel)
            open = false
            closing = false
        }
    }

    IpcHandler {
        target: "ctrl"
        function toggle(): void { root.toggle() }
        function show(): void   { if (!root.open) root.toggle() }
        function hide(): void   { root.close() }
    }

    // ── Navigation ──
    function navigate(dir) {
        if (level === 1) {
            if (slot === "center") {
                var t = ({up:"top",down:"bottom",left:"left",right:"right"})[dir]
                if (t) { slot = t; level = 3; sub = firstSub(slot); action = firstAction() }
                return
            }
            var same = ((dir === "up"    && slot === "top")    ||
                        (dir === "down"  && slot === "bottom") ||
                        (dir === "left"  && slot === "left")   ||
                        (dir === "right" && slot === "right"))
            if (same) { level = 3; sub = firstSub(slot); action = firstAction(); return }
            var opp = ((dir === "down"  && slot === "top")    ||
                       (dir === "up"    && slot === "bottom") ||
                       (dir === "right" && slot === "left")   ||
                       (dir === "left"  && slot === "right"))
            if (opp) { slot = "center"; return }
            var t2 = ({up:"top",down:"bottom",left:"left",right:"right"})[dir]
            if (t2 && t2 !== slot) slot = t2
        }
        else if (level === 3) {
            var subs = subList(slot)
            var subKeys = subs.map(function(s){ return s.key })
            var subIdx = subKeys.indexOf(sub)
            var acts = actList()
            var actKeys = acts.map(function(a){ return a.key })
            var actIdx = actKeys.indexOf(action)

            if (dir === "up" || dir === "down") {
                if (dir === "up") {
                    if (subIdx > 0) { sub = subKeys[subIdx - 1]; action = firstAction() }
                    else            { level = 1; sub = ""; action = ""; slot = "center" }
                } else {
                    if (subIdx < subKeys.length - 1) { sub = subKeys[subIdx + 1]; action = firstAction() }
                    else                              { level = 1; sub = ""; action = ""; slot = "center" }
                }
            } else if (dir === "left" || dir === "right") {
                var towardsDetail = (slot === "left") ? "left" : "right"
                if (dir === towardsDetail) {
                    if (actIdx < actKeys.length - 1) action = actKeys[actIdx + 1]
                } else {
                    if (actIdx > 0) action = actKeys[actIdx - 1]
                    else { level = 1; sub = ""; action = ""; slot = "center" }
                }
            }
        }
    }

    // ── Détection écran actif ──
    property string activeMonitor: ""
    Process {
        id: getMonitorProc
        running: root.open
        command: ["sh","-c","hyprctl cursorpos -j | python3 -c \"\nimport sys,json,subprocess\npos=json.load(sys.stdin)\nmons=json.loads(subprocess.check_output(['hyprctl','monitors','-j']))\nfor m in mons:\n    x,y=m['x'],m['y']\n    w,h=m['width'],m['height']\n    if x<=pos['x']<x+w and y<=pos['y']<y+h:\n        print(m['name'])\n        break\n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = this.text.trim()
                if (n !== "") root.activeMonitor = n
            }
        }
    }

    // ═══════════════════════════════════
    //   PANEL
    // ═══════════════════════════════════
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: modelData.width
            implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.open && modelData.name === root.activeMonitor)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: root.open || root.closing
            readonly property bool isActive: modelData.name === root.activeMonitor

            // Fond dim
            Rectangle {
                anchors.fill: parent
                color: "#0b0906"
                opacity: (root.open && !root.closing) ? 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            // ── Conteneur clavier + croix ──
            Item {
                anchors.fill: parent
                visible: isActive
                opacity: (root.open && !root.closing) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                focus: root.open && !root.closing && isActive

                Keys.onPressed: function(e) {
                    var k = e.key
                    if (k === Qt.Key_Escape)                          { root.back();          e.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                        root.activateCurrent(); e.accepted = true
                    }
                    else if (k === Qt.Key_W || k === Qt.Key_Up)       { root.navigate("up");    e.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down)     { root.navigate("down");  e.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left)     { root.navigate("left");  e.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right)    { root.navigate("right"); e.accepted = true }
                }

                // ── Croix avec pan ──
                Item {
                    id: cross
                    anchors.centerIn: parent
                    width: 1; height: 1

                    // Pan global : le cross glisse pour amener le slot focusé vers le centre
                    anchors.horizontalCenterOffset: {
                        if (root.level !== 3) return 0
                        if (root.slot === "left")  return  root.panShiftH
                        if (root.slot === "right") return -root.panShiftH
                        return 0
                    }
                    anchors.verticalCenterOffset: {
                        if (root.level !== 3) return 0
                        if (root.slot === "top")    return  root.panShiftV
                        if (root.slot === "bottom") return -root.panShiftV
                        return 0
                    }
                    Behavior on anchors.horizontalCenterOffset {
                        NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                    }
                    Behavior on anchors.verticalCenterOffset {
                        NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                    }

                    NierArrow { axis: "top" }
                    NierArrow { axis: "bottom" }
                    NierArrow { axis: "left" }
                    NierArrow { axis: "right" }

                    Slot {
                        slotKey: "center"
                        title: "MENU"
                        subtitle: "CONTROL CENTER"
                        anchors.centerIn: parent
                        isCenter: true
                    }
                    Slot {
                        slotKey: "top"
                        title: "Connexion"
                        subtitle: "Wi-Fi · Bluetooth"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: (root.open && !root.closing) ? -root.slotGapV : 0
                        Behavior on anchors.verticalCenterOffset {
                            NumberAnimation { duration: 560; easing.type: Easing.OutCubic; }
                        }
                    }
                    Slot {
                        slotKey: "bottom"
                        title: "Audio"
                        subtitle: "Output · Volume"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: (root.open && !root.closing) ? root.slotGapV : 0
                        Behavior on anchors.verticalCenterOffset {
                            NumberAnimation { duration: 560; easing.type: Easing.OutCubic; }
                        }
                    }
                    Slot {
                        slotKey: "left"
                        title: "Quickshare"
                        subtitle: "File transfer"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: (root.open && !root.closing) ? -root.slotGapH : 0
                        Behavior on anchors.horizontalCenterOffset {
                            NumberAnimation { duration: 560; easing.type: Easing.OutCubic; }
                        }
                    }
                    Slot {
                        slotKey: "right"
                        title: "Notifications"
                        subtitle: "History · DND"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: (root.open && !root.closing) ? root.slotGapH : 0
                        Behavior on anchors.horizontalCenterOffset {
                            NumberAnimation { duration: 560; easing.type: Easing.OutCubic; }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //   COMPOSANTS
    // ═══════════════════════════════════════════════════════════════════

    // ── Flèche NieR ──
    component NierArrow: Item {
        id: ar
        property string axis: "top"
        width: 36; height: 36

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter:   parent.verticalCenter
        anchors.horizontalCenterOffset: {
            if (axis === "left")  return -root.slotGapH / 2
            if (axis === "right") return  root.slotGapH / 2
            return 0
        }
        anchors.verticalCenterOffset: {
            if (axis === "top")    return -root.slotGapV / 2
            if (axis === "bottom") return  root.slotGapV / 2
            return 0
        }

        readonly property bool isFocused:
              (root.slot === axis) && (root.level === 1 || root.level === 3)

        readonly property real restRotation:
              axis === "top"    ? 180 :
              axis === "bottom" ? 0   :
              axis === "left"   ? 90  : -90
        readonly property real focusRotation:
              axis === "top"    ? 0   :
              axis === "bottom" ? 180 :
              axis === "left"   ? -90 : 90

        Image {
            anchors.fill: parent
            source: root.arrowPng
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectFit
            smooth: true
            rotation: ar.isFocused ? ar.focusRotation : ar.restRotation
        }

        opacity: {
            if (!root.open && !root.closing) return 0
            if (root.closing) return 0.55  // toutes au repos pendant la fermeture
            if (isFocused)  return 1.0
            if (root.level >= 2) return 0.18
            return 0.55
        }
        Behavior on opacity { NumberAnimation { duration: 320 } }
    }

    // ── Slot ──
    component Slot: Item {
        id: sl
        property string slotKey: ""
        property string title: ""
        property string subtitle: ""
        property bool   isCenter: false

        readonly property bool isFocus:    root.slot === slotKey
        readonly property bool isOpposite: !isCenter && (
              (slotKey === "top"    && root.slot === "bottom") ||
              (slotKey === "bottom" && root.slot === "top")    ||
              (slotKey === "left"   && root.slot === "right")  ||
              (slotKey === "right"  && root.slot === "left"))
        readonly property bool isInL3: isFocus && root.level === 3

        width: 280; height: 56
        z: isFocus ? 5 : 2

        opacity: {
            if (!root.open && !root.closing) return 0
            if (root.level === 3) {
                if (isFocus) return 1.0
                if (isCenter) return 0.4
                return 0.28
            }
            // L1 (et closing) : tous les slots clairs
            return 1.0
        }
        Behavior on opacity { NumberAnimation { duration: 320 } }

        // Marqueur focus à gauche
        Item {
            id: focusMark
            width: 18; height: 18
            anchors.right: boxWrap.left
            anchors.rightMargin: 14
            anchors.verticalCenter: boxWrap.verticalCenter
            opacity: (sl.isFocus && !sl.isInL3 && !sl.isCenter) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Rectangle {
                width: 8; height: 8; rotation: 45
                color: root.colInk
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
            Canvas {
                anchors.left: parent.left
                anchors.leftMargin: 12
                width: 8; height: 12
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    ctx.strokeStyle = root.colInk
                    ctx.lineWidth = 1.4
                    ctx.beginPath()
                    ctx.moveTo(0, 1)
                    ctx.lineTo(width-1, height/2)
                    ctx.lineTo(0, height-1)
                    ctx.stroke()
                }
            }
        }

        // ── Box wrapper ──
        Item {
            id: boxWrap
            anchors.fill: parent
            opacity: sl.isInL3 ? 0 : 1
            transform: Translate {
                x: sl.isFocus && !sl.isCenter ? 8 : 0
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: 240 } }

            Rectangle {
                id: box
                anchors.fill: parent
                color: sl.isCenter ? root.colCard : root.colCardSoft
                border.color: root.colInk
                border.width: 1

                // Onglet asymétrique
                Rectangle {
                    visible: !sl.isCenter
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    color: sl.isFocus ? root.colHi : root.colInk
                    Behavior on color { ColorAnimation { duration: 220 } }
                    z: 2
                }

                // Bordure interne
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    color: "transparent"
                    border.color: root.colInk
                    border.width: 1
                    opacity: sl.isFocus ? 0.6 : (sl.isCenter ? 0.5 : 0.35)
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    z: 2
                }

                // Coins en L
                Repeater {
                    model: sl.isCenter ? 0 : 4
                    Item {
                        width: 8; height: 8
                        x: (index === 0 || index === 2) ? 6 : (box.width - 8)
                        y: (index < 2) ? -2 : (box.height - 8 + 2)
                        z: 3
                        Rectangle {
                            width: 8; height: 2
                            color: root.colInk
                            y: (index < 2) ? 0 : 6
                        }
                        Rectangle {
                            width: 2; height: 8
                            color: root.colInk
                            x: (index === 0 || index === 2) ? 0 : 6
                        }
                    }
                }

                // Curtain wipe
                Rectangle {
                    id: curtain
                    anchors.fill: parent
                    color: root.colCard
                    transform: Scale {
                        origin.x: 0; origin.y: 0
                        xScale: sl.isFocus && !sl.isCenter ? 1 : 0
                        yScale: 1
                        Behavior on xScale {
                            NumberAnimation { duration: 380; easing.type: Easing.InOutQuint }
                        }
                    }
                    z: 1
                    visible: !sl.isCenter
                }

                // Indicateur (carré sombre à gauche)
                Rectangle {
                    visible: !sl.isCenter
                    width: 14; height: 14
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.colInk
                    opacity: sl.isFocus ? 0 : 0.85
                    transform: Scale {
                        origin.x: 7; origin.y: 7
                        xScale: sl.isFocus ? 0 : 1
                        yScale: sl.isFocus ? 0 : 1
                        Behavior on xScale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on yScale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    z: 3
                }

                // Label
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: sl.isCenter ? 0 : 42
                    anchors.right: parent.right
                    anchors.rightMargin: sl.isCenter ? 0 : 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    z: 4
                    Text {
                        text: sl.title
                        font.family: "Inter"
                        font.pixelSize: sl.isCenter ? 15 : 13
                        font.weight: Font.Medium
                        font.letterSpacing: sl.isCenter ? 6 : 0.3
                        color: root.colInk
                        horizontalAlignment: sl.isCenter ? Text.AlignHCenter : Text.AlignLeft
                        anchors.horizontalCenter: sl.isCenter ? parent.horizontalCenter : undefined
                    }
                    Text {
                        text: sl.subtitle
                        font.family: "Inter"
                        font.pixelSize: sl.isCenter ? 9 : 10
                        color: root.colInkSoft
                        font.letterSpacing: sl.isCenter ? 1 : 0.2
                        horizontalAlignment: sl.isCenter ? Text.AlignHCenter : Text.AlignLeft
                        anchors.horizontalCenter: sl.isCenter ? parent.horizontalCenter : undefined
                    }
                }
            }
        }

        // Losanges aux coins du center
        Repeater {
            model: sl.isCenter ? 4 : 0
            Rectangle {
                width: 5; height: 5
                color: root.colInk
                rotation: 45
                x: (index === 0 || index === 2) ? -3 : (sl.width - 3)
                y: (index < 2) ? -3 : (sl.height - 3)
                z: 6
                opacity: sl.isFocus ? 1 : 0
                transform: Scale {
                    origin.x: 2.5; origin.y: 2.5
                    xScale: sl.isFocus ? 1 : 0
                    yScale: sl.isFocus ? 1 : 0
                    Behavior on xScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    Behavior on yScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                }
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
        }

        // Sub-items
        Column {
            anchors.centerIn: parent
            spacing: 12
            opacity: sl.isInL3 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 280 } }

            Repeater {
                model: sl.isInL3 ? root.subList(sl.slotKey) : []
                SubItem {
                    subItem: modelData
                    parentSlot: sl.slotKey
                    enterDelay: 280 + index * 80
                }
            }
        }

        // Détails
        Item {
            id: detailsItem
            visible: sl.isInL3 && (root.detailKey() in root.details)
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 280 } }

            anchors.left: sl.slotKey === "left" ? undefined : parent.right
            anchors.right: sl.slotKey === "left" ? parent.left : undefined
            anchors.leftMargin: 30
            anchors.rightMargin: 30
            anchors.verticalCenter: parent.verticalCenter

            width: 300
            height: detailsCol.implicitHeight + 36

            // Box stylisée style NieR (fond beige soft + bordure + onglet)
            Rectangle {
                anchors.fill: parent
                color: root.colCardSoft
                border.color: root.colInk
                border.width: 1
            }
            // Bordure interne décalée
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                color: "transparent"
                border.color: root.colInk
                border.width: 1
                opacity: 0.35
            }
            // Coins en L
            Repeater {
                model: 4
                Item {
                    width: 8; height: 8
                    x: (index === 0 || index === 2) ? 6 : (detailsItem.width - 8)
                    y: (index < 2) ? -2 : (detailsItem.height - 8 + 2)
                    z: 3
                    Rectangle { width: 8; height: 2; color: root.colInk; y: (index < 2) ? 0 : 6 }
                    Rectangle { width: 2; height: 8; color: root.colInk; x: (index === 0 || index === 2) ? 0 : 6 }
                }
            }

            Column {
                id: detailsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 18
                spacing: 0

                Text {
                    id: detailH3
                    property string targetText: root.detailH3().toUpperCase()
                    text: targetText
                    onTargetTextChanged: scrambleH3.start()
                    font.family: "Inter"
                    font.pixelSize: 11
                    font.letterSpacing: 5
                    font.weight: Font.Medium
                    color: root.colInk
                    opacity: 0.7

                    ScrambleAnim {
                        id: scrambleH3
                        target: detailH3
                        duration: 320
                    }
                }

                Item { width: 1; height: 8 }

                Rectangle {
                    width: 36
                    height: 1
                    color: root.colInk
                    opacity: 0.5
                }

                Item { width: 1; height: 14 }

                Row {
                    spacing: 10
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.detailOn() ? root.colHi : root.colInkSoft
                        SequentialAnimation on opacity {
                            running: root.detailOn()
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 1100 }
                            NumberAnimation { to: 1.0; duration: 1100 }
                        }
                    }
                    Text {
                        id: detailStatus
                        property string targetText: root.detailStatus()
                        text: targetText
                        onTargetTextChanged: scrambleStatus.start()
                        font.family: "Inter"
                        font.pixelSize: 12
                        color: root.colInk
                        anchors.verticalCenter: parent.verticalCenter

                        ScrambleAnim {
                            id: scrambleStatus
                            target: detailStatus
                            duration: 380
                        }
                    }
                }

                Item { width: 1; height: 14 }

                // Liste scrollable des actions (Toggle + réseaux/devices/etc.)
                Item {
                    width: parent.width
                    // Hauteur adaptative : min 1 action, max 8 visibles
                    property int actCount: root.actList().length
                    height: Math.min(actCount, 8) * 40
                    visible: actCount > 0

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: actCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: actCol
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: sl.isInL3 ? root.actList() : []
                                ActionBtn {
                                    actionData: modelData
                                    isFocus: root.action === modelData.key
                                    enterDelay: 200 + Math.min(index, 5) * 60
                                    width: actCol.width
                                }
                            }
                        }
                    }
                }
            }
        }

        // Hover / clic sur la box
        MouseArea {
            anchors.fill: boxWrap
            hoverEnabled: true
            onEntered: if (root.level === 1) root.slot = sl.slotKey
            onClicked: {
                if (root.level === 1) {
                    root.slot = sl.slotKey
                    if (!sl.isCenter) {
                        root.level = 3
                        root.sub = root.firstSub(sl.slotKey)
                        root.action = root.firstAction()
                    }
                }
            }
            visible: !sl.isInL3
        }
    }

    // ── Sub-item ──
    component SubItem: Item {
        id: si
        property var    subItem
        property string parentSlot: ""
        property int    enterDelay: 0

        readonly property bool isFocus: root.sub === subItem.key

        width: 220
        height: 36

        opacity: 0
        transform: Translate { id: subT; x: -12 }
        Component.onCompleted: enterAnim.start()
        SequentialAnimation {
            id: enterAnim
            PauseAnimation { duration: si.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: si; property: "opacity"; to: 1; duration: 380; easing.type: Easing.InOutQuint }
                NumberAnimation { target: subT; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: si.isFocus ? root.colInk : "transparent"
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }

        Rectangle {
            anchors.fill: parent
            color: root.colCard
            transform: Scale {
                origin.x: 0; origin.y: 0
                xScale: si.isFocus ? 1 : 0
                yScale: 1
                Behavior on xScale { NumberAnimation { duration: 320; easing.type: Easing.InOutQuint } }
            }
            z: 1
        }

        Rectangle {
            width: 6; height: 6
            color: root.colInk
            rotation: 45
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: si.isFocus ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            z: 3
        }

        Text {
            id: subTxt
            property string targetText: si.subItem.label
            text: targetText
            onTargetTextChanged: subScramble.start()
            anchors.centerIn: parent
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.colInk
            z: 2

            ScrambleAnim {
                id: subScramble
                target: subTxt
                duration: 280
            }
        }

        // Re-scramble quand devient focus
        onIsFocusChanged: if (isFocus) subScramble.start()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                if (root.level >= 2 && root.slot === si.parentSlot) {
                    root.sub = si.subItem.key
                    root.level = 3
                    root.action = root.firstAction()
                }
            }
        }
    }

    // ── Bouton d'action ──
    component ActionBtn: Item {
        id: btn
        property var    actionData
        property bool   isFocus: false
        property int    enterDelay: 0

        height: 32

        opacity: 0
        transform: Translate { id: btnT; x: -8 }
        Component.onCompleted: enterAnim2.start()
        SequentialAnimation {
            id: enterAnim2
            PauseAnimation { duration: btn.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: btn; property: "opacity"; to: 1; duration: 380; easing.type: Easing.InOutQuint }
                NumberAnimation { target: btnT; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
            ScriptAction { script: btnScramble.start() }
        }

        Rectangle {
            anchors.fill: parent
            color: btn.isFocus ? root.colInk : "transparent"
            border.color: root.colInk
            border.width: 1
            opacity: btn.isFocus ? 1 : 0.5
            Behavior on color { ColorAnimation { duration: 220 } }
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // Curtain au focus
        Rectangle {
            anchors.fill: parent
            color: root.colInk
            transform: Scale {
                origin.x: 0; origin.y: 0
                xScale: btn.isFocus ? 1 : 0
                yScale: 1
                Behavior on xScale { NumberAnimation { duration: 280; easing.type: Easing.InOutQuint } }
            }
            z: 1
        }

        // Marqueur losange à gauche au focus
        Rectangle {
            width: 6; height: 6; rotation: 45
            color: root.colCard
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: btn.isFocus ? 1 : 0
            transform: Scale {
                origin.x: 3; origin.y: 3
                xScale: btn.isFocus ? 1 : 0
                yScale: btn.isFocus ? 1 : 0
                Behavior on xScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on yScale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            z: 3
        }

        Text {
            id: btnTxt
            property string targetText: btn.actionData.label.toUpperCase()
            text: targetText
            onTargetTextChanged: btnScramble.start()
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            font.family: "Inter"
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 2.5
            color: btn.isFocus ? root.colCard : root.colInk
            Behavior on color { ColorAnimation { duration: 200 } }
            z: 2

            ScrambleAnim {
                id: btnScramble
                target: btnTxt
                duration: 280
            }
        }

        // Re-scramble quand on devient focus
        onIsFocusChanged: if (isFocus) btnScramble.start()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: if (root.level === 3) root.action = btn.actionData.key
            onClicked: {
                root.action = btn.actionData.key
                root.dispatchAction(root.slot, root.sub, btn.actionData.key)
            }
        }
    }

    // ── Animation scramble (texte qui se révèle lettre par lettre) ──
    component ScrambleAnim: QtObject {
        id: anim
        property Item target: null   // doit avoir une property "targetText"
        property int duration: 280
        property string chars: "▸◆▪▫░▒▓█/\\|-_=+*"
        property int _elapsed: 0
        property int _step: 16

        property var _timer: Timer {
            interval: anim._step
            repeat: true
            running: false
            onTriggered: {
                if (!anim.target) { running = false; return }
                anim._elapsed += anim._step
                var t = Math.min(1, anim._elapsed / anim.duration)
                var finalText = anim.target.targetText
                var len = finalText.length
                var result = ""
                for (var i = 0; i < len; i++) {
                    var reveal = i / len
                    if (t > reveal + 0.15) {
                        result += finalText[i]
                    } else if (t > reveal) {
                        result += anim.chars[Math.floor(Math.random() * anim.chars.length)]
                    } else {
                        result += "\u00A0"
                    }
                }
                anim.target.text = result
                if (t >= 1) {
                    anim.target.text = finalText
                    running = false
                }
            }
        }

        function start() {
            if (!target) return
            _elapsed = 0
            _timer.running = true
        }
    }
}
