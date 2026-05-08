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
    readonly property int  slotGapV: 150
    readonly property int  slotGapH: 350
    readonly property int  panShiftV: 320   // vertical (top/bottom) : centre l'ensemble sub+settings
    readonly property int  panShiftH: 700   // horizontal (left/right) : sub-menu traverse l'écran

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
                    var lock = (n.security && n.security !== "" && n.security !== "--") ? " ⚿" : "  "
                    acts.push({
                        key: "connect:" + n.ssid,
                        label: prefix + n.ssid + "  " + sigBars + lock
                    })
                }
            }
            return acts
        }
        // Bluetooth
        if (key === "top.bluetooth") {
            var acts2 = [{key:"toggle", label: btEnabled ? "Disable Bluetooth" : "Enable Bluetooth"}]
            if (btEnabled) {
                acts2.push({key: "scan", label: btScanning ? "◉ Scanning… (tap to stop)" : "⌕ Scan for new devices"})
                for (var j = 0; j < btDevices.length; j++) {
                    var d = btDevices[j]
                    var prefix = d.connected ? "✓ " : (d.paired ? "· " : "+ ")
                    var label = prefix + d.name
                    var aKey
                    if (d.connected)      aKey = "disconnect:" + d.mac
                    else if (d.paired)    aKey = "connect:"    + d.mac
                    else                  aKey = "pair:"       + d.mac
                    acts2.push({key: aKey, label: label})
                    if (d.paired) {
                        acts2.push({key: "remove:" + d.mac, label: "    × Remove " + d.name})
                    }
                }
            }
            return acts2
        }
        // Audio Output : liste des sinks
        if (key === "bottom.output") {
            var acts3 = []
            for (var k = 0; k < audioSinks.length; k++) {
                var s = audioSinks[k]
                var pre = s.isDefault ? "✓ " : "  "
                acts3.push({key: "set-sink:" + s.name, label: pre + s.description})
            }
            if (acts3.length === 0) acts3.push({key:"none", label:"No outputs found"})
            return acts3
        }
        // Audio Volume : pas de liste, juste le slider (rendu séparément)
        if (key === "bottom.volume") {
            return [{key:"mute-toggle", label: audioMuted ? "Unmute" : "Mute"}]
        }
        // Quickshare Send (qshare.py)
        if (key === "left.send") {
            var acts4 = []
            acts4.push({key:"pick-file", label: pendingFilePath
                ? "✓ " + pendingFilePath.split("/").pop()
                : "⌕ Pick file with Yazi"})
            if (pendingFilePath !== "") {
                acts4.push({key:"clear-file", label: "× Cancel selection"})
            }
            acts4.push({key:"toggle-tunnel",
                label: qshareTunnel ? "[✓] Tunnel (Internet)" : "[ ] Tunnel (Internet)"})
            acts4.push({key:"toggle-keepalive",
                label: qshareKeepAlive ? "[✓] Keep alive" : "[ ] Keep alive"})
            if (pendingFilePath !== "") {
                acts4.push({key:"start-send", label: "→ Generate QR"})
            }
            return acts4
        }
        // Quickshare Receive (qshare.py)
        if (key === "left.receive") {
            var acts5 = []
            var dirShort = qshareOutputDir.replace(home, "~")
            acts5.push({key:"cycle-output", label: "Output: " + dirShort + " ▸"})
            acts5.push({key:"toggle-tunnel",
                label: qshareTunnel ? "[✓] Tunnel (Internet)" : "[ ] Tunnel (Internet)"})
            acts5.push({key:"toggle-keepalive",
                label: qshareKeepAlive ? "[✓] Keep alive" : "[ ] Keep alive"})
            acts5.push({key:"start-recv", label: "→ Open receiver"})
            return acts5
        }
        // Notifications History
        if (key === "right.history") {
            var acts6 = []
            for (var p = 0; p < notifications.length; p++) {
                var n2 = notifications[p]
                acts6.push({
                    key: "notif:" + p,
                    label: n2.summary || "(empty)",
                    body: n2.body || "",
                    app: n2.app || "",
                    appIcon: n2.appIcon || "",
                    category: n2.category || "",
                    urgency: n2.urgency || "normal",
                    timeout: n2.timeout >= 0 ? n2.timeout : -1,
                    desktopEntry: n2.desktopEntry || "",
                    actions: n2.actions || [],
                    notifIdx: p
                })
            }
            return acts6
        }
        // Notifications DND
        if (key === "right.dnd") {
            return [{key:"toggle-dnd", label: dndEnabled ? "Disable DND" : "Enable DND"}]
        }
        // Autres : actions statiques du dictionnaire details
        var dd = root.details[key]
        return dd ? dd.actions : []
    }

    function detailH3() {
        var key = detailKey()
        if (key === "top.wifi")          return "Wi-Fi"
        if (key === "top.bluetooth")     return "Bluetooth"
        if (key === "bottom.output")     return "Audio Output"
        if (key === "bottom.volume")     return "Volume"
        if (key === "left.send")         return "Send Files"
        if (key === "left.receive")      return "Receive Files"
        if (key === "right.history")     return "Notifications"
        if (key === "right.dnd")         return "Do Not Disturb"
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
            return "Enabled · " + btDevices.length + " device" + (btDevices.length !== 1 ? "s" : "")
        }
        if (key === "bottom.output") {
            // Trouver la description du default sink
            for (var i = 0; i < audioSinks.length; i++) {
                if (audioSinks[i].isDefault) return audioSinks[i].description
            }
            return audioDefaultSink || "—"
        }
        if (key === "bottom.volume") {
            if (audioMuted) return "Muted"
            return Math.round(audioVolume * 100) + "%"
        }
        if (key === "left.send") {
            if (pendingFilePath === "") return "Ready · pick a file"
            return qshareTunnel ? "Tunnel mode" : "LAN mode"
        }
        if (key === "left.receive") {
            return qshareTunnel ? "Tunnel · " + qshareOutputDir.replace(home, "~")
                                : "LAN · " + qshareOutputDir.replace(home, "~")
        }
        if (key === "right.history") {
            return notifications.length + " notification" + (notifications.length !== 1 ? "s" : "")
        }
        if (key === "right.dnd") {
            return dndEnabled ? "Active" : "Off"
        }
        var d2 = root.details[key]
        return d2 ? d2.status : ""
    }
    function detailOn() {
        var key = detailKey()
        if (key === "top.wifi")          return wifiEnabled
        if (key === "top.bluetooth")     return btEnabled
        if (key === "bottom.output")     return true
        if (key === "bottom.volume")     return !audioMuted
        if (key === "left.send")         return pendingFilePath !== ""
        if (key === "left.receive")      return qshareUrl !== ""
        if (key === "right.history")     return notifications.length > 0
        if (key === "right.dnd")         return dndEnabled
        var d3 = root.details[key]
        return d3 ? d3.on : false
    }
    // ── Données système : Wi-Fi ──
    property bool   wifiEnabled: false
    property string wifiCurrentSSID: ""
    property var    wifiNetworks: []   // [{ssid, signal, security, active}]
    property string wifiPromptSSID: ""   // SSID en cours de saisie de mot de passe (vide = pas de prompt)
    property string wifiError: ""        // message d'erreur après échec connexion

    Timer {
        interval: 3000; running: root.open && root.slot === "top"; repeat: true; triggeredOnStart: true
        onTriggered: pollWifi.running = true
    }
    Process {
        id: pollWifi
        // Récupère état radio + liste des réseaux scannés
        command: ["sh","-c",
            "echo \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null | head -40"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                root.wifiEnabled = (lines[0] || "").trim() === "enabled"
                var seen = ({})  // dedup par SSID
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
                    // Garde l'entrée existante si elle a un meilleur signal ou est active
                    if (seen[ssid]) {
                        if (seen[ssid].active) continue
                        if (seen[ssid].signal >= signal && !inUse) continue
                    }
                    seen[ssid] = {ssid: ssid, signal: signal, security: security, active: inUse}
                }
                // Reconstruit en array, triée par signal décroissant (active en premier)
                var nets = []
                for (var k in seen) nets.push(seen[k])
                nets.sort(function(a,b){
                    if (a.active && !b.active) return -1
                    if (!a.active && b.active) return 1
                    return b.signal - a.signal
                })
                root.wifiNetworks = nets
                root.wifiCurrentSSID = current
            }
        }
    }

    // ── Données système : Bluetooth ──
    property bool   btEnabled: false
    property var    btDevices: []   // [{name, mac, connected, paired}]
    property bool   btScanning: false
    property string wifiPasswordInput: ""

    // ── Données système : Audio ──
    property var    audioSinks: []        // [{name, description, default}]
    property string audioDefaultSink: ""
    property real   audioVolume: 0.5      // 0.0 - 1.0
    property bool   audioMuted: false

    Timer {
        interval: 1500; running: root.open && root.slot === "bottom"; repeat: true; triggeredOnStart: true
        onTriggered: pollAudio.running = true
    }
    Process {
        id: pollAudio
        command: ["sh","-c",
            "echo \"DEFAULT:$(pactl get-default-sink 2>/dev/null)\"; " +
            "echo \"VOLUME:$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\\d+%' | head -1 | tr -d '%')\"; " +
            "echo \"MUTE:$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')\"; " +
            "pactl list short sinks 2>/dev/null | while read line; do " +
            "  id=$(echo \"$line\" | awk '{print $1}'); " +
            "  name=$(echo \"$line\" | awk '{print $2}'); " +
            "  desc=$(pactl list sinks 2>/dev/null | awk -v n=\"$name\" '$1==\"Name:\" && $2==n{f=1} f && /Description:/{$1=\"\"; print substr($0,2); exit}'); " +
            "  echo \"SINK:$name|$desc\"; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var sinks = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    if (line.indexOf("DEFAULT:") === 0) {
                        root.audioDefaultSink = line.substring(8).trim()
                    } else if (line.indexOf("VOLUME:") === 0) {
                        var v = parseInt(line.substring(7))
                        if (!isNaN(v)) root.audioVolume = v / 100
                    } else if (line.indexOf("MUTE:") === 0) {
                        root.audioMuted = line.substring(5).trim() === "yes"
                    } else if (line.indexOf("SINK:") === 0) {
                        var parts = line.substring(5).split("|")
                        sinks.push({
                            name: parts[0],
                            description: parts[1] || parts[0],
                            isDefault: parts[0] === root.audioDefaultSink
                        })
                    }
                }
                // Marquer le default sink en re-passant (au cas où il a été lu après les sinks)
                for (var j = 0; j < sinks.length; j++) {
                    sinks[j].isDefault = sinks[j].name === root.audioDefaultSink
                }
                root.audioSinks = sinks
            }
        }
    }

    // ── Notifications via IPC vers Notifications.qml (qui possède le bus DBus) ──
    property bool dndEnabled: false
    property var notifications: []     // [{id, summary, body, app, ts}]
    property int expandedNotifIdx: -1  // index de la notif expanded (-1 = aucune)

    // Poll l'historique des notifs depuis le daemon Notifications.qml via IPC
    Timer {
        interval: 1500
        running: root.open && root.slot === "right"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pollNotifsHistory.running = true
            pollNotifsDnd.running = true
        }
    }
    Process {
        id: pollNotifsHistory
        command: ["sh","-c","qs ipc call notifs getHistory 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text.trim() || "[]")
                    root.notifications = parsed
                } catch(e) {
                    root.notifications = []
                }
            }
        }
    }
    Process {
        id: pollNotifsDnd
        command: ["sh","-c","qs ipc call notifs getDnd 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.dndEnabled = this.text.trim() === "true"
            }
        }
    }
    // Process pour les actions vers le daemon notifs
    Process {
        id: notifActProc
        command: ["sh","-c","true"]
        running: false
    }

    // Helpers : appellent l'IPC du daemon
    function dismissNotif(idx) {
        notifActProc.command = ["sh","-c","qs ipc call notifs dismissAt " + idx]
        notifActProc.running = true
        // Refresh local immédiat (optimiste)
        var list = root.notifications.slice()
        list.splice(idx, 1)
        root.notifications = list
    }
    function dismissAllNotifs() {
        notifActProc.command = ["sh","-c","qs ipc call notifs clearAll"]
        notifActProc.running = true
        root.notifications = []
    }
    function invokeNotif(idx) {
        // Le daemon fait invoke + dismiss en un appel
        dismissNotif(idx)
    }
    function setDnd(state) {
        notifActProc.command = ["sh","-c","qs ipc call notifs setDnd " + (state ? "true" : "false")]
        notifActProc.running = true
        dndEnabled = state
    }

    // ── Données système : Quickshare (qshare.py) ──
    property string pendingFilePath: ""   // chemin de fichier sélectionné, en attente d'envoi

    // ── État qshare ──
    property bool   qshareTunnel:    false
    property bool   qshareKeepAlive: false
    property string qshareOutputDir: home + "/Downloads"
    property string qshareUrl:       ""     // URL active (modal visible si non vide)
    property string qshareQrPath:    ""     // chemin du PNG QR
    property string qshareLabel:     ""     // ex. "envoi : photo.jpg" ou "réception → ~/Downloads"
    property string qshareLastTick:  ""     // dernier fichier transféré (pour feedback)
    property bool   qshareCancelled: false
    readonly property string qshareScriptPath: xdgConfigHome + "/quickshell/scripts/qshare.py"
    readonly property string qshareEventFile:  "/tmp/qshare-events"
    readonly property string qshareQrFile:     "/tmp/qshare-qr.png"

    readonly property var qshareOutputDirs: [
        home + "/Downloads",
        home + "/Pictures",
        home + "/Documents",
        "/tmp"
    ]

    Timer {
        interval: 3000; running: root.open && root.slot === "left"; repeat: true; triggeredOnStart: true
        onTriggered: qshareEventReader.running = qshareProc.running
    }

    // Process qui lance Yazi pour picker un fichier
    Process {
        id: yaziProc
        running: false
        command: ["sh","-c","true"]
        // Le résultat est écrit par yazi dans /tmp/yzi-out, on le lira après
    }
    // Timer qui vérifie l'existence du fichier choisi par yazi
    Timer {
        id: yaziCheckTimer
        interval: 500
        repeat: true
        property int count: 0
        onTriggered: {
            count += 1
            yaziReadProc.running = true
            if (count >= 60) { running = false; count = 0 }   // 30s max
        }
    }
    Process {
        id: yaziReadProc
        command: ["sh","-c","cat /tmp/yzi-out 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var path = this.text.trim()
                if (path && path !== root.pendingFilePath) {
                    root.pendingFilePath = path
                    yaziCheckTimer.running = false
                    yaziCheckTimer.count = 0
                    // Rouvre le ControlCenter sur left.send avec le fichier sélectionné
                    if (!root.open) {
                        root.open = true
                        root.closing = false
                        root.level = 3
                        root.slot = "left"
                        root.sub = "send"
                        root.action = root.firstAction()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //   qshare.py — process + event polling + lancement/arrêt
    // ═══════════════════════════════════════════════════════════════════

    function startQshare(mode, filePath) {
        // Reset state
        root.qshareUrl = ""
        root.qshareQrPath = ""
        root.qshareLastTick = ""
        root.qshareCancelled = false

        // Cleanup ancien event/QR file (sync via touch)
        cleanupQshareProc.command = ["sh","-c",
            "rm -f " + qshareEventFile + " " + qshareQrFile + "; " +
            "touch " + qshareEventFile]
        cleanupQshareProc.running = true

        // Construit la commande
        var args = [qshareScriptPath, mode]
        if (mode === "send") {
            args.push(filePath)
            qshareLabel = "envoi : " + filePath.split("/").pop()
        } else {
            args.push("-o"); args.push(qshareOutputDir)
            qshareLabel = "réception → " + qshareOutputDir.replace(home, "~")
        }
        if (qshareTunnel)    args.push("--tunnel")
        if (qshareKeepAlive) args.push("--keep-alive")
        args.push("--qr-out");     args.push(qshareQrFile)
        args.push("--event-file"); args.push(qshareEventFile)

        qshareProc.command = args
        qshareProc.running = true
        qshareEventPoll.running = true
    }

    function stopQshare() {
        qshareCancelled = true
        qshareProc.running = false   // SIGTERM
        qshareEventPoll.running = false
        qshareUrl = ""
        qshareQrPath = ""
        // Reset pendingFilePath après un envoi
        pendingFilePath = ""
    }

    Process { id: cleanupQshareProc; command: ["sh","-c","true"]; running: false }

    Process {
        id: qshareProc
        running: false
        command: ["sh","-c","true"]
        // stdout/stderr ignorés — on s'en remet à l'event-file
        onRunningChanged: {
            if (!running) {
                // Process terminé → ferme le modal après un petit délai pour
                // laisser le temps de voir le tick final
                qshareEventPoll.running = false
                qshareCloseTimer.restart()
            }
        }
    }

    Timer {
        id: qshareCloseTimer
        interval: qshareCancelled ? 0 : 600
        repeat: false
        onTriggered: {
            qshareUrl = ""
            qshareQrPath = ""
            qshareLastTick = ""
            // Reset pendingFilePath après un transfert send réussi
            if (!qshareCancelled && root.sub === "send") {
                pendingFilePath = ""
            }
        }
    }

    // Poll l'event-file pour récupérer URL/QR/TICK/DONE
    Timer {
        id: qshareEventPoll
        interval: 250
        repeat: true
        running: false
        onTriggered: qshareEventReader.running = true
    }

    Process {
        id: qshareEventReader
        running: false
        command: ["sh","-c","cat " + root.qshareEventFile + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    if (line.indexOf("URL ") === 0) {
                        root.qshareUrl = line.substring(4)
                    } else if (line.indexOf("QR ") === 0) {
                        root.qshareQrPath = line.substring(3)
                    } else if (line.indexOf("TICK ") === 0) {
                        root.qshareLastTick = line.substring(5)
                    } else if (line === "DONE") {
                        // Le process va s'arrêter tout seul, le onRunningChanged gère
                    } else if (line === "CANCELLED") {
                        root.qshareCancelled = true
                    }
                }
            }
        }
    }

    Timer {
        interval: 3000; running: root.open && root.slot === "top"; repeat: true; triggeredOnStart: true
        onTriggered: pollBt.running = true
    }
    Process {
        id: pollBt
        // Récupère powered + liste de TOUS les devices (paired et découverts)
        // avec leur état connected et paired pour différencier
        command: ["sh","-c",
            "echo \"$(bluetoothctl show 2>/dev/null | grep -i 'powered:' | awk '{print $2}')\"; " +
            "bluetoothctl devices 2>/dev/null | while read line; do " +
            "  mac=$(echo \"$line\" | awk '{print $2}'); " +
            "  name=$(echo \"$line\" | cut -d' ' -f3-); " +
            "  info=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  conn=$(echo \"$info\" | grep -i 'Connected:' | awk '{print $2}'); " +
            "  paired=$(echo \"$info\" | grep -i 'Paired:' | awk '{print $2}'); " +
            "  trusted=$(echo \"$info\" | grep -i 'Trusted:' | awk '{print $2}'); " +
            "  echo \"$mac|$name|$conn|$paired|$trusted\"; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                root.btEnabled = (lines[0] || "").trim() === "yes"
                var seen = ({})
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length < 4) continue
                    var mac = parts[0]
                    if (!mac || seen[mac]) continue
                    seen[mac] = {
                        mac: mac,
                        name: parts[1] || mac,
                        connected: (parts[2] || "").trim() === "yes",
                        paired:    (parts[3] || "").trim() === "yes",
                        trusted:   (parts[4] || "").trim() === "yes"
                    }
                }
                var devices = []
                for (var k in seen) devices.push(seen[k])
                // Trier : connectés > paired > non-paired (découverts), puis nom
                devices.sort(function(a,b){
                    if (a.connected !== b.connected) return a.connected ? -1 : 1
                    if (a.paired    !== b.paired)    return a.paired ? -1 : 1
                    return a.name.localeCompare(b.name)
                })
                root.btDevices = devices
            }
        }
    }

    // Process pour scan BT
    Process {
        id: btScanProc
        command: ["sh","-c","bluetoothctl --timeout 30 scan on"]
        running: false
    }
    // Stop scan automatique après 30s
    Timer {
        id: btScanStopTimer
        interval: 30000
        repeat: false
        onTriggered: { root.btScanning = false }
    }
    // Re-poll plus fréquent quand on scan
    Timer {
        interval: 1500
        running: root.btScanning && root.open
        repeat: true
        onTriggered: pollBt.running = true
    }

    // Process pour submission du password Wi-Fi (sépare actProc pour capture stderr)
    Process {
        id: wifiSubmitProc
        command: ["sh","-c","true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var output = this.text.trim()
                if (output.indexOf("successfully activated") >= 0 || output === "") {
                    root.wifiPromptSSID = ""
                    root.wifiPasswordInput = ""
                    root.wifiError = ""
                } else {
                    // erreur, on reste sur le prompt
                    root.wifiError = "Connection failed"
                }
                refreshTimer.restart()
            }
        }
    }

    // ── Process pour exécuter les actions ──
    Process { id: actProc; command: ["sh","-c","true"]; running: false }

    // Refresh state quand on change de slot
    onSlotChanged: {
        if (slot === "top")    { pollWifi.running = true; pollBt.running = true }
        if (slot === "bottom") { pollAudio.running = true }
        if (slot === "right")  {
            pollNotifsHistory.running = true
            pollNotifsDnd.running = true
        }
    }

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
                // Trouver le réseau dans la liste pour vérifier la sécurité
                var net = null
                for (var i = 0; i < wifiNetworks.length; i++) {
                    if (wifiNetworks[i].ssid === ssid) { net = wifiNetworks[i]; break }
                }
                // Si déjà actif, déconnexion
                if (net && net.active) {
                    cmd = "nmcli con down id '" + ssid + "' 2>/dev/null || nmcli dev disconnect $(nmcli -t -f DEVICE,TYPE dev | grep wifi | head -1 | cut -d: -f1)"
                }
                // Si réseau ouvert, connexion directe
                else if (net && (net.security === "" || net.security === "--")) {
                    cmd = "nmcli dev wifi connect '" + ssid.replace(/'/g, "'\\''") + "'"
                }
                // Si réseau sécurisé : ouvrir le prompt
                else {
                    wifiPromptSSID = ssid
                    wifiError = ""
                    return
                }
            } else if (actionKey === "submit-password") {
                // Soumission du mot de passe via le prompt
                cmd = "nmcli dev wifi connect '" + wifiPromptSSID.replace(/'/g, "'\\''") +
                      "' password '" + wifiPasswordInput.replace(/'/g, "'\\''") + "' 2>&1"
                wifiSubmitProc.command = ["sh","-c", cmd]
                wifiSubmitProc.running = true
                return
            } else if (actionKey === "cancel-prompt") {
                wifiPromptSSID = ""
                wifiPasswordInput = ""
                wifiError = ""
                return
            }
        }
        // ── Bluetooth ──
        else if (slotKey === "top" && subKey === "bluetooth") {
            if (actionKey === "toggle") {
                cmd = "bluetoothctl power " + (btEnabled ? "off" : "on")
            } else if (actionKey === "scan") {
                btScanning = !btScanning
                if (btScanning) {
                    btScanProc.running = true
                    btScanStopTimer.restart()
                } else {
                    actProc.command = ["sh","-c","bluetoothctl --timeout 1 scan off"]
                    actProc.running = true
                }
                return
            } else if (actionKey.indexOf("connect:") === 0) {
                var mac = actionKey.substring(8)
                cmd = "bluetoothctl trust " + mac + " 2>/dev/null; bluetoothctl connect " + mac
            } else if (actionKey.indexOf("disconnect:") === 0) {
                var mac2 = actionKey.substring(11)
                cmd = "bluetoothctl disconnect " + mac2
            } else if (actionKey.indexOf("pair:") === 0) {
                var mac3 = actionKey.substring(5)
                cmd = "bluetoothctl pair " + mac3 + " && bluetoothctl trust " + mac3 + " && sleep 0.5 && bluetoothctl connect " + mac3
            } else if (actionKey.indexOf("remove:") === 0) {
                var mac4 = actionKey.substring(7)
                cmd = "bluetoothctl disconnect " + mac4 + " 2>/dev/null; bluetoothctl remove " + mac4
            }
        }
        // ── Audio Output ──
        else if (slotKey === "bottom" && subKey === "output") {
            if (actionKey.indexOf("set-sink:") === 0) {
                var sink = actionKey.substring(9)
                cmd = "pactl set-default-sink '" + sink + "'"
            }
        }
        // ── Audio Volume ──
        else if (slotKey === "bottom" && subKey === "volume") {
            if (actionKey === "mute-toggle") {
                cmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle"
            } else if (actionKey.indexOf("set-volume:") === 0) {
                var vol = actionKey.substring(11)
                cmd = "pactl set-sink-volume @DEFAULT_SINK@ " + vol + "%"
            }
        }
        // ── Quickshare Send (qshare.py) ──
        else if (slotKey === "left" && subKey === "send") {
            if (actionKey === "pick-file") {
                // Lance le terminal flottant avec yazi, puis ferme le ControlCenter
                cmd =
                    "rm -f /tmp/yzi-out; " +
                    "if command -v foot >/dev/null 2>&1; then " +
                    "  foot --app-id qs-yazi-picker yazi --chooser-file=/tmp/yzi-out & " +
                    "elif command -v alacritty >/dev/null 2>&1; then " +
                    "  alacritty --class qs-yazi-picker -e yazi --chooser-file=/tmp/yzi-out & " +
                    "elif command -v kitty >/dev/null 2>&1; then " +
                    "  kitty --class qs-yazi-picker yazi --chooser-file=/tmp/yzi-out & " +
                    "elif command -v wezterm >/dev/null 2>&1; then " +
                    "  wezterm start --class qs-yazi-picker -- yazi --chooser-file=/tmp/yzi-out & " +
                    "else " +
                    "  notify-send 'qshare' 'No supported terminal found (foot/alacritty/kitty/wezterm)'; " +
                    "fi"
                actProc.command = ["sh","-c", cmd]
                actProc.running = true
                yaziCheckTimer.count = 0
                yaziCheckTimer.running = true
                // Ferme le ControlCenter pour libérer le focus à la fenêtre yazi
                close()
                return
            } else if (actionKey === "clear-file") {
                pendingFilePath = ""
                return
            } else if (actionKey === "toggle-tunnel") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "toggle-keepalive") {
                qshareKeepAlive = !qshareKeepAlive
                return
            } else if (actionKey === "start-send") {
                if (pendingFilePath === "") return
                root.startQshare("send", pendingFilePath)
                return
            }
        }
        // ── Quickshare Receive (qshare.py) ──
        else if (slotKey === "left" && subKey === "receive") {
            if (actionKey === "toggle-tunnel") {
                qshareTunnel = !qshareTunnel
                return
            } else if (actionKey === "toggle-keepalive") {
                qshareKeepAlive = !qshareKeepAlive
                return
            } else if (actionKey === "cycle-output") {
                var dirs = qshareOutputDirs
                var idx = dirs.indexOf(qshareOutputDir)
                qshareOutputDir = dirs[(idx + 1) % dirs.length]
                return
            } else if (actionKey === "start-recv") {
                root.startQshare("recv", "")
                return
            }
        }
        // ── Notifications History ──
        else if (slotKey === "right" && subKey === "history") {
            if (actionKey === "clear-all") {
                dismissAllNotifs()
                return
            } else if (actionKey.indexOf("notif:") === 0) {
                var idx = parseInt(actionKey.substring(6))
                invokeNotif(idx)
                return
            } else if (actionKey === "none") {
                return
            }
        }
        // ── Notifications DND ──
        else if (slotKey === "right" && subKey === "dnd") {
            if (actionKey === "toggle-dnd") {
                setDnd(!dndEnabled)
                return
            }
        }

        if (cmd) {
            actProc.command = ["sh","-c", cmd]
            actProc.running = true
            // refresh state après une seconde
            refreshTimer.restart()
            // Pour les actions BT pair/connect/disconnect/remove, refresh répété
            if (slotKey === "top" && subKey === "bluetooth" && actionKey !== "toggle" && actionKey !== "scan") {
                btRepeatRefresh.count = 0
                btRepeatRefresh.running = true
            }
        }
    }
    Timer {
        id: refreshTimer
        interval: 800; repeat: false
        onTriggered: { pollWifi.running = true; pollBt.running = true }
    }
    // Refresh BT répété après une action pair/connect (peut prendre 5-10s)
    Timer {
        id: btRepeatRefresh
        interval: 1500
        repeat: true
        property int count: 0
        onTriggered: {
            pollBt.running = true
            count += 1
            if (count >= 6) { running = false; count = 0 }
        }
    }

    function activateCurrent() {
        if (level === 3 && action) {
            // Cas spécial notifs : 1er Enter = expand, 2e Enter = invoke
            if (slot === "right" && sub === "history" && action.indexOf("notif:") === 0) {
                var idx = parseInt(action.substring(6))
                if (expandedNotifIdx === idx) {
                    invokeNotif(idx)
                } else {
                    expandedNotifIdx = idx
                }
                return
            }
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
        interval: 290  // attendre la fin de l'animation des slots (250ms + marge)
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
                id: keyHandler
                anchors.fill: parent
                visible: isActive
                opacity: (root.open && !root.closing) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                focus: root.open && !root.closing && isActive

                // Reprendre le focus clavier quand le prompt Wi-Fi se ferme
                Connections {
                    target: root
                    function onWifiPromptSSIDChanged() {
                        if (root.wifiPromptSSID === "") {
                            keyHandler.forceActiveFocus()
                        }
                    }
                }

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
                            NumberAnimation { duration: 250; easing.type: Easing.InCirc; }
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
                            NumberAnimation { duration: 250; easing.type: Easing.InCirc; }
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
                            NumberAnimation { duration: 250; easing.type: Easing.InCirc; }
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
                            NumberAnimation { duration: 250; easing.type: Easing.InCirc; }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════
                //   QR Modal qshare (visible quand qshareUrl !== "")
                // ═══════════════════════════════════════════════════════
                Rectangle {
                    id: qrBackdrop
                    anchors.fill: parent
                    color: "#000000"
                    opacity: (root.qshareUrl !== "" && isActive) ? 0.55 : 0
                    visible: opacity > 0
                    z: 100
                    Behavior on opacity { NumberAnimation { duration: 280 } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.stopQshare()
                        enabled: root.qshareUrl !== ""
                    }
                }

                Item {
                    id: qrModal
                    anchors.centerIn: parent
                    width: 380; height: 500
                    z: 101
                    opacity: (root.qshareUrl !== "" && isActive) ? 1 : 0
                    visible: opacity > 0
                    scale: (root.qshareUrl !== "" && isActive) ? 1.0 : 0.92
                    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on scale   { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                    // Fond carte
                    Rectangle {
                        anchors.fill: parent
                        color: root.colCard
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
                            x: (index === 0 || index === 2) ? 6 : (qrModal.width - 8)
                            y: (index < 2) ? -2 : (qrModal.height - 8 + 2)
                            z: 3
                            Rectangle { width: 8; height: 2; color: root.colInk; y: (index < 2) ? 0 : 6 }
                            Rectangle { width: 2; height: 8; color: root.colInk; x: (index === 0 || index === 2) ? 0 : 6 }
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 12

                        // Header
                        Text {
                            text: "QSHARE"
                            font.family: "Inter"
                            font.pixelSize: 11
                            font.letterSpacing: 5
                            font.weight: Font.Medium
                            color: root.colInk
                            opacity: 0.6
                        }
                        Rectangle { width: 36; height: 1; color: root.colInk; opacity: 0.5 }

                        Item { width: 1; height: 4 }

                        // Label (envoi/réception)
                        Text {
                            width: parent.width
                            text: root.qshareLabel
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: root.colInk
                            elide: Text.ElideMiddle
                        }

                        // QR area
                        Item {
                            width: parent.width
                            height: 280
                            Rectangle {
                                anchors.centerIn: parent
                                width: 280; height: 280
                                color: root.colHi
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    source: root.qshareQrPath !== ""
                                            ? "file://" + root.qshareQrPath + "?t=" + Date.now()
                                            : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: false
                                    cache: false
                                    asynchronous: true
                                }
                                // Loading state
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.qshareQrPath === ""
                                    text: "GENERATING…"
                                    font.family: "Inter"
                                    font.pixelSize: 10
                                    font.letterSpacing: 3
                                    color: root.colCard
                                    opacity: 0.6
                                }
                            }
                        }

                        // URL en petit
                        Text {
                            width: parent.width
                            text: root.qshareUrl
                            font.family: "Iosevka, monospace"
                            font.pixelSize: 9
                            color: root.colInk
                            opacity: 0.55
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Tick / Status
                        Text {
                            width: parent.width
                            text: root.qshareLastTick !== ""
                                  ? "✓ " + root.qshareLastTick
                                  : "Scan with phone…"
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.letterSpacing: 1.5
                            color: root.colInk
                            opacity: 0.7
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Bouton Cancel/Stop en bas-droite
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 14
                        width: 90; height: 26
                        color: cancelMA.containsMouse ? root.colInk : "transparent"
                        border.color: root.colInk
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 180 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.qshareKeepAlive ? "× STOP" : "× CANCEL"
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.letterSpacing: 2.5
                            font.weight: Font.Medium
                            color: cancelMA.containsMouse ? root.colCard : root.colInk
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        MouseArea {
                            id: cancelMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stopQshare()
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
            anchors.verticalCenterOffset: {
                if (sl.slotKey === "top")    return -200
                if (sl.slotKey === "bottom") return  100
                return 0
            }
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
                        // largeur max : panneau total - dot - margin
                        width: detailsCol.width - 26
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap

                        ScrambleAnim {
                            id: scrambleStatus
                            target: detailStatus
                            duration: 380
                        }
                    }
                }

                Item { width: 1; height: 14 }

                // Liste scrollable des actions
                // Pour les notifs (right.history) : composant NotifBtn avec expand
                // Pour le reste : ActionBtn standard
                Item {
                    id: actListContainer
                    width: parent.width
                    property bool isNotifList: sl.slotKey === "right" && root.sub === "history"
                    property int actCount: root.actList().length
                    // Hauteur adaptative max 8 visibles, mais hauteur d'item plus grande pour notifs expanded
                    height: isNotifList
                        ? Math.min(actCount === 0 ? 1 : Math.max(actCount, 1), 5) * 56 + (root.expandedNotifIdx >= 0 ? 90 : 0)
                        : Math.min(actCount, 8) * 40
                    visible: actCount > 0 || isNotifList   // toujours visible pour notifs (pour msg vide)

                    // Message si liste vide (notifs)
                    Text {
                        anchors.centerIn: parent
                        visible: actListContainer.isNotifList && actListContainer.actCount === 0
                        text: "No notifications"
                        font.family: "Inter"
                        font.pixelSize: 11
                        color: root.colInkSoft
                        font.letterSpacing: 1
                    }

                    Flickable {
                        id: actFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: actCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Auto-scroll vers la notif focusée
                        function scrollToFocus() {
                            var acts = root.actList()
                            for (var i = 0; i < acts.length; i++) {
                                if (acts[i].key === root.action) {
                                    var itemH = actListContainer.isNotifList ? 56 : 40
                                    var itemY = i * (itemH + 8)
                                    if (itemY < contentY) {
                                        contentY = Math.max(0, itemY - 4)
                                    } else if (itemY + itemH > contentY + height) {
                                        contentY = Math.min(contentHeight - height, itemY + itemH - height + 4)
                                    }
                                    return
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onActionChanged() { actFlick.scrollToFocus() }
                        }

                        Column {
                            id: actCol
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: sl.isInL3 ? root.actList() : []
                                Loader {
                                    width: actCol.width
                                    sourceComponent: actListContainer.isNotifList ? notifBtnComp : actionBtnComp
                                    property var actionData: modelData
                                    property bool isFocus: root.action === modelData.key
                                    property int enterDelay: 200 + Math.min(index, 5) * 60
                                }
                            }
                        }
                    }

                    // Indicateur de scroll visible (track + thumb)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: root.colInk
                        opacity: 0.15
                        visible: actFlick.contentHeight > actFlick.height

                        Rectangle {
                            x: 0
                            width: 2
                            color: root.colInk
                            opacity: 0.7
                            y: actFlick.contentHeight > 0
                                ? (actFlick.contentY / actFlick.contentHeight) * parent.height
                                : 0
                            height: actFlick.contentHeight > 0
                                ? Math.max(20, (actFlick.height / actFlick.contentHeight) * parent.height)
                                : 0
                        }
                    }
                }

                // ── Footer pinned : "Clear All" pour les notifs (visible si notifs > 0) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "right" && root.sub === "history" && root.notifications.length > 0
                    height: visible ? 48 : 0

                    Item { width: 1; height: 14 }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        height: 32
                        color: clearAllMA.containsMouse ? root.colInk : "transparent"
                        border.color: root.colInk
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Text {
                            anchors.centerIn: parent
                            text: "× CLEAR ALL"
                            font.family: "Inter"
                            font.pixelSize: 11
                            font.letterSpacing: 2.5
                            font.weight: Font.Medium
                            color: clearAllMA.containsMouse ? root.colCard : root.colInk
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            id: clearAllMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissAllNotifs()
                        }
                    }
                }

                // ── Composants pour la liste ──
                Component {
                    id: actionBtnComp
                    ActionBtn {
                        actionData: parent.actionData
                        isFocus: parent.isFocus
                        enterDelay: parent.enterDelay
                    }
                }
                Component {
                    id: notifBtnComp
                    NotifBtn {
                        notifData: parent.actionData
                        isFocus: parent.isFocus
                        enterDelay: parent.enterDelay
                    }
                }

                // ── Slider Volume (visible quand bottom.volume) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "bottom" && root.sub === "volume"
                    height: visible ? 60 : 0

                    Item { width: 1; height: 14 }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        spacing: 6

                        // Track + thumb
                        Rectangle {
                            id: volTrack
                            width: parent.width
                            height: 24
                            color: "transparent"
                            border.color: root.colInk
                            border.width: 1

                            // Bordure interne
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                color: "transparent"
                                border.color: root.colInk
                                border.width: 1
                                opacity: 0.35
                            }

                            // Fill (volume actuel)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                width: (parent.width - 6) * (root.audioMuted ? 0 : root.audioVolume)
                                color: root.colInk
                                opacity: root.audioMuted ? 0.3 : 1.0
                                Behavior on width { NumberAnimation { duration: 120 } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // MouseArea : clic = mute toggle, drag = set volume
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                property bool dragging: false
                                property real lastX: 0

                                onPressed: function(e) {
                                    if (e.button === Qt.RightButton) {
                                        root.dispatchAction("bottom","volume","mute-toggle")
                                        return
                                    }
                                    dragging = true
                                    lastX = e.x
                                    setVol(e.x)
                                }
                                onReleased: dragging = false
                                onPositionChanged: function(e) {
                                    if (dragging) setVol(e.x)
                                }
                                onClicked: function(e) {
                                    // Click simple sans drag : mute/unmute si sur la cellule à droite (au-delà de la ligne actuelle)
                                    // Sinon set vol
                                    if (Math.abs(e.x - lastX) < 3) {
                                        // C'était juste un click : on a déjà appelé setVol, c'est ok
                                    }
                                }
                                onWheel: function(e) {
                                    var delta = e.angleDelta.y > 0 ? 5 : -5
                                    var newVol = Math.max(0, Math.min(100, Math.round(root.audioVolume * 100) + delta))
                                    root.dispatchAction("bottom","volume","set-volume:" + newVol)
                                }

                                function setVol(x) {
                                    var w = volTrack.width - 6
                                    var v = Math.max(0, Math.min(1, (x - 3) / w))
                                    var pct = Math.round(v * 100)
                                    root.dispatchAction("bottom","volume","set-volume:" + pct)
                                }
                            }
                        }

                        // Indication mute clickable
                        Text {
                            text: root.audioMuted ? "Muted · Click track to unmute" : "Right-click track to mute · Scroll to adjust"
                            font.family: "Inter"
                            font.pixelSize: 9
                            color: root.colInk
                            opacity: 0.5
                            font.letterSpacing: 1
                        }
                    }
                }

                // ── Prompt mot de passe Wi-Fi (visible quand wifiPromptSSID est set) ──
                Item {
                    width: parent.width
                    visible: sl.slotKey === "top" && root.sub === "wifi" && root.wifiPromptSSID !== ""
                    height: visible ? 110 : 0

                    Item { width: 1; height: 14 }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        spacing: 8

                        Text {
                            text: "PASSWORD · " + root.wifiPromptSSID
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                            color: root.colInk
                            opacity: 0.7
                        }

                        Rectangle {
                            width: parent.width
                            height: 32
                            color: root.colCard
                            border.color: root.colInk
                            border.width: 1

                            TextInput {
                                id: pwInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.colInk
                                font.family: "Inter"
                                font.pixelSize: 13
                                echoMode: TextInput.Password
                                clip: true
                                focus: root.wifiPromptSSID !== ""
                                onTextChanged: root.wifiPasswordInput = text
                                onAccepted: root.dispatchAction("top","wifi","submit-password")
                                Keys.onEscapePressed: root.dispatchAction("top","wifi","cancel-prompt")
                                // Reset à l'ouverture du prompt
                                Connections {
                                    target: root
                                    function onWifiPromptSSIDChanged() {
                                        if (root.wifiPromptSSID !== "") {
                                            pwInput.text = ""
                                            pwInput.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }

                        // Erreur si applicable
                        Text {
                            visible: root.wifiError !== ""
                            text: root.wifiError
                            font.family: "Inter"
                            font.pixelSize: 10
                            color: "#a04030"
                        }

                        // Boutons Connect / Cancel
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 110; height: 28
                                color: root.colInk
                                Text {
                                    anchors.centerIn: parent
                                    text: "CONNECT"
                                    font.family: "Inter"
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                    font.weight: Font.Medium
                                    color: root.colCard
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.dispatchAction("top","wifi","submit-password")
                                }
                            }
                            Rectangle {
                                width: 80; height: 28
                                color: "transparent"
                                border.color: root.colInk
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "CANCEL"
                                    font.family: "Inter"
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                    font.weight: Font.Medium
                                    color: root.colInk
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.dispatchAction("top","wifi","cancel-prompt")
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

    // ── Bouton Notification (avec expand/collapse) ──
    component NotifBtn: Item {
        id: nbtn
        property var notifData
        property bool isFocus: false
        property int enterDelay: 0
        readonly property bool expanded: root.expandedNotifIdx === notifData.notifIdx

        height: 48

        opacity: 0
        transform: Translate { id: nbtnT; x: -8 }
        Component.onCompleted: nbtnEnter.start()
        SequentialAnimation {
            id: nbtnEnter
            PauseAnimation { duration: nbtn.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: nbtn; property: "opacity"; to: 1; duration: 380; easing.type: Easing.InOutQuint }
                NumberAnimation { target: nbtnT; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
        }

        // Bordure
        Rectangle {
            anchors.fill: parent
            color: nbtn.isFocus ? root.colInk : "transparent"
            border.color: root.colInk
            border.width: 1
            opacity: nbtn.isFocus ? 1 : 0.5
            Behavior on color { ColorAnimation { duration: 220 } }
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // Curtain
        Rectangle {
            anchors.fill: parent
            color: root.colInk
            transform: Scale {
                origin.x: 0; origin.y: 0
                xScale: nbtn.isFocus ? 1 : 0
                yScale: 1
                Behavior on xScale { NumberAnimation { duration: 280; easing.type: Easing.InOutQuint } }
            }
            z: 1
        }

        // Marqueur losange focus
        Rectangle {
            width: 5; height: 5; rotation: 45
            color: root.colCard
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: nbtn.isFocus ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            z: 3
        }

        // Contenu
        Item {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 36   // place pour le bouton expand
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            z: 2

            // App name (petit, en haut)
            Text {
                id: appLabel
                anchors.top: parent.top
                anchors.left: parent.left
                text: nbtn.notifData.app ? nbtn.notifData.app.toUpperCase() : ""
                font.family: "Inter"
                font.pixelSize: 8
                font.letterSpacing: 1.5
                color: nbtn.isFocus ? root.colCard : root.colInk
                opacity: 0.6
                visible: text !== ""
            }

            // Summary
            Text {
                id: summaryLabel
                anchors.top: appLabel.visible ? appLabel.bottom : parent.top
                anchors.topMargin: appLabel.visible ? 1 : 0
                anchors.left: parent.left
                anchors.right: parent.right
                text: nbtn.notifData.label
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: nbtn.isFocus ? root.colCard : root.colInk
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            // Body (visible quand expanded)
            Text {
                id: bodyLabel
                anchors.top: summaryLabel.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                visible: nbtn.expanded && text !== ""
                text: nbtn.notifData.body
                font.family: "Inter"
                font.pixelSize: 10
                color: nbtn.isFocus ? root.colCard : root.colInk
                opacity: 0.85
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            // Metadata (visible quand expanded) : urgency, category, timeout, actions
            Text {
                anchors.top: bodyLabel.visible ? bodyLabel.bottom : summaryLabel.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                visible: nbtn.expanded
                text: {
                    var bits = []
                    var d = nbtn.notifData
                    if (d.urgency && d.urgency !== "normal") bits.push(d.urgency.toUpperCase())
                    if (d.category) bits.push("cat:" + d.category)
                    if (d.timeout > 0) bits.push((d.timeout/1000) + "s")
                    if (d.desktopEntry) bits.push(d.desktopEntry)
                    if (d.actions && d.actions.length > 0) {
                        bits.push(d.actions.length + " action" + (d.actions.length > 1 ? "s" : ""))
                    }
                    return bits.join(" · ")
                }
                font.family: "Inter"
                font.pixelSize: 8
                font.letterSpacing: 1
                color: nbtn.isFocus ? root.colCard : root.colInk
                opacity: 0.55
                wrapMode: Text.WordWrap
            }
        }

        // Bouton expand ▸ / ▾
        Item {
            id: expandBtn
            width: 24; height: parent.height
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            z: 4

            Text {
                anchors.centerIn: parent
                text: nbtn.expanded ? "▾" : "▸"
                font.family: "Inter"
                font.pixelSize: 12
                color: nbtn.isFocus ? root.colCard : root.colInk
                opacity: 0.8
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (nbtn.expanded) root.expandedNotifIdx = -1
                    else root.expandedNotifIdx = nbtn.notifData.notifIdx
                }
            }
        }

        // MouseArea pour clic sur le corps : 1er clic = expand, 2e clic = invoke
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 24   // ne pas couvrir le bouton expand
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: 0
            onEntered: root.action = nbtn.notifData.key
            onClicked: {
                if (nbtn.expanded) {
                    // déjà expandu → invoke source
                    root.invokeNotif(nbtn.notifData.notifIdx)
                } else {
                    // pas encore expanded → expand
                    root.expandedNotifIdx = nbtn.notifData.notifIdx
                }
            }
        }

        // Quand expanded, on agrandit la hauteur
        states: State {
            name: "expanded"
            when: nbtn.expanded
            PropertyChanges { target: nbtn; height: 140 }
        }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }


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
