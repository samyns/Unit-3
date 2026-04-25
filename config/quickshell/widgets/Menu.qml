import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property int lw: 780
    readonly property int lh: 540
    property real screenW: 1920
    property real screenH: 1080

    property bool   menuOpen:        false
    property bool   wipeHideRunning: false  // reste true pendant l'animation de fermeture
    property string currentCat: "all"
    property string searchQuery: ""
    property int    focusIdx:   0
    property string clockStr:   "--:--:--"

    implicitWidth:  screenW
    implicitHeight: screenH

    // Palette
    readonly property color paper:     "#d6cfb5"
    readonly property color ink:       "#463f2e"
    readonly property color inkStrong: "#2e2a1f"
    readonly property color inkSoft:   "#7a7358"
    readonly property color lineSoft:  Qt.rgba(70/255,63/255,46/255,0.25)
    readonly property color lineVsoft: Qt.rgba(70/255,63/255,46/255,0.12)
    readonly property color accent:    "#6e2a2a"

    // Apps
    property var  apps: []
    property bool appsLoaded: false

    readonly property var catLabels: ({
        "all":"ALL","dev":"DEVELOP","sys":"SYSTEM","net":"NETWORK",
        "media":"MEDIA","office":"OFFICE","graphics":"GRAPHICS",
        "games":"GAMES","other":"OTHER"
    })

    readonly property var catOrder: ["all","dev","sys","net","media","office","graphics","games","other"]

    readonly property var catKeys: {
        var present = {"all": true}
        for (var i = 0; i < apps.length; i++) present[apps[i].cat] = true
        return catOrder.filter(function(k) { return present[k] })
    }

    readonly property var filteredApps: {
        var q = searchQuery.toLowerCase().trim()
        return apps.filter(function(a) {
            var catOk = currentCat === "all" || a.cat === currentCat
            var qOk = !q || a.name.toLowerCase().indexOf(q) >= 0 || a.meta.toLowerCase().indexOf(q) >= 0
            return catOk && qOk
        })
    }

    // ── Lecture .desktop ──
    Process {
        id: desktopReader
        command: ["bash", Qt.resolvedUrl("../list-apps.sh").toString().replace("file://","")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var result = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    var parts = line.split("|")
                    if (parts.length < 2) continue
                    var name      = parts[0].trim()
                    var desktopId = parts[1].trim()
                    var cats      = parts[2] || ""
                    var rawExec   = (parts[3] || "").replace(/%[A-Za-z]/g,"").trim()
                    if (!name || !desktopId) continue
                    // Utiliser l'exec brut si dispo, sinon le desktop ID
                    var launchCmd = rawExec || desktopId

                    var cat = "other"
                    if (/Development|IDE|TextEditor|Debugger/i.test(cats))          cat = "dev"
                    else if (/WebBrowser|Email|Chat|Network|FileTransfer/i.test(cats)) cat = "net"
                    else if (/Audio|Video|Player|Music/i.test(cats))                cat = "media"
                    else if (/Office|Spreadsheet|WordProcessor|Presentation/i.test(cats)) cat = "office"
                    else if (/Graphics|Photography|2DGraphics/i.test(cats))         cat = "graphics"
                    else if (/Game|Emulator/i.test(cats))                           cat = "games"
                    else if (/System|Utility|Monitor|Settings/i.test(cats))         cat = "sys"

                    var nl = name.toLowerCase()
                    var ico = "·"
                    if (/terminal|kitty|alacritty|console/.test(nl)) ico = "▸"
                    else if (/firefox|chromium|browser/.test(nl))     ico = "○"
                    else if (/nvim|vim|editor|code|helix/.test(nl))   ico = "⌥"
                    else if (/file|yazi|ranger/.test(nl))             ico = "▤"
                    else if (/btop|htop|monitor/.test(nl))            ico = "▲"
                    else if (/music|audio|pulse/.test(nl))            ico = "♪"
                    else if (/video|mpv|vlc/.test(nl))                ico = "▶"
                    else if (/lock|hyprlock/.test(nl))                ico = "⬡"
                    else if (/libre|office|calc|writer/.test(nl))     ico = "≡"
                    else if (/gimp|inkscape|image/.test(nl))          ico = "⬜"
                    else if (cat === "dev")      ico = "⌥"
                    else if (cat === "net")      ico = "○"
                    else if (cat === "media")    ico = "▶"
                    else if (cat === "sys")      ico = "◈"
                    else if (cat === "office")   ico = "≡"

                    result.push({
                        id:        String(i+1).padStart(2,"0"),
                        name:      name,
                        cat:       cat,
                        meta:      desktopId,
                        desktopId: launchCmd,
                        cmd:       launchCmd,
                        icon:      ico
                    })
                }
                root.apps = result
                root.appsLoaded = true
            }
        }
    }

    // Un seul Process — sh -c pour tout
    Process {
        id: launchProc
        property string pending: ""
        command: ["sh", "-c", pending]
        running: false
    }

    function launchApp(cmd) {
        if (!cmd) return
        // nohup + redirection évite EPIPE pour les apps Electron (Discord, etc.)
        launchProc.pending = "nohup " + cmd + " > /dev/null 2>&1 &"
        launchProc.running = true
        root.closeMenu()
    }

    // Lancer une commande directe (footer)
    function launch(cmd) {
        if (!cmd || cmd === "") return
        launchProc.pending = "nohup " + cmd + " > /dev/null 2>&1 &"
        launchProc.running = true
        root.closeMenu()
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var d = new Date()
            root.clockStr = String(d.getHours()).padStart(2,"0") + ":"
                + String(d.getMinutes()).padStart(2,"0") + ":"
                + String(d.getSeconds()).padStart(2,"0")
        }
    }

    Timer {
        id: focusTimer; interval: 50; repeat: true; running: false
        property int attempts: 0
        onTriggered: {
            searchInput.forceActiveFocus()
            attempts++
            if (attempts >= 8) { running = false; attempts = 0 }
        }
    }

    Component.onCompleted: {
        var d = new Date()
        clockStr = String(d.getHours()).padStart(2,"0") + ":"
            + String(d.getMinutes()).padStart(2,"0") + ":"
            + String(d.getSeconds()).padStart(2,"0")
        desktopReader.running = true
    }

    // ── Overlay ──
    Rectangle {
        anchors.fill: parent
        color: root.menuOpen ? Qt.rgba(184/255,175/255,147/255,0.55) : "transparent"
        visible: true
        Behavior on color { ColorAnimation { duration: 260 } }
        MouseArea {
            anchors.fill: parent
            enabled: root.menuOpen
            onClicked: root.closeMenu()
        }
    }

    // ── Panel host (clip + wipe) ──
    Item {
        id: panelHost
        x: (root.screenW - root.lw) / 2
        y: (root.screenH - root.lh) / 2
        width:  root.lw
        height: root.lh
        clip:   true
        visible: root.menuOpen || wipeReveal.running || wipeHide.running

        // Contenu
        Rectangle {
            id:     panelContent
            anchors.fill: parent
            color:  root.paper
            border.color: root.ink; border.width: 1

            // Grille fine
            Repeater {
                model: Math.floor(root.lw/20)+1
                Rectangle { x:index*20; y:0; width:1; height:root.lh; color:root.lineVsoft }
            }
            Repeater {
                model: Math.floor(root.lh/20)+1
                Rectangle { x:0; y:index*20; width:root.lw; height:1; color:root.lineVsoft }
            }

            // Clic n'importe où → focus sur search
            MouseArea {
                anchors.fill: parent; z: -1
                onClicked: searchInput.forceActiveFocus()
                propagateComposedEvents: true
            }

            // Scan line
            Rectangle {
                id: scanLine; x:0; width:root.lw; height:2; z:20; opacity:0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position:0.0; color:"transparent" }
                    GradientStop { position:0.5; color:root.accent }
                    GradientStop { position:1.0; color:"transparent" }
                }
                NumberAnimation on y {
                    id: scanAnim; from:0; to:root.lh; duration:700; running:false
                    easing.type: Easing.Linear
                    onStarted:  scanLine.opacity = 1
                    onFinished: scanLine.opacity = 0
                }
            }

            // ── HEADER ──
            Item {
                id: header; width:parent.width; height:52

                Row {
                    anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                              leftMargin:28; rightMargin:28 }
                    Row {
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Text { text:"SYSTEM"; font.pixelSize:11; font.letterSpacing:3.5; font.weight:Font.Medium; color:root.inkStrong }
                        Rectangle { width:24; height:1; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                        Text { text:"システム"; font.pixelSize:10; font.letterSpacing:2; color:root.inkSoft }
                    }
                    Item { width:parent.width - 340; height:1 }
                    Row {
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Item {
                            width:120; height:16; clip:true
                            Text {
                                id:lhTick
                                text: root.clockStr + " · " + root.apps.length + " APPS · "
                                font.pixelSize:9; font.letterSpacing:1.5; color:root.inkSoft; y:2
                                NumberAnimation on x {
                                    from:120; to:-lhTick.implicitWidth
                                    duration:12000; loops:Animation.Infinite; running:root.menuOpen
                                }
                            }
                        }
                        Text { text:"SESSION 0471"; font.pixelSize:9; font.letterSpacing:2.5; color:root.inkSoft }
                    }
                }
                Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
            }

            // ── BODY ──
            Item {
                id: body
                anchors { top:header.bottom; bottom:footer.top }
                width: parent.width

                // Sidebar
                Item {
                    id:sidebar; width:160; height:parent.height
                    Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.lineSoft }
                    Column {
                        anchors { top:parent.top; topMargin:16 }
                        width:parent.width

                        Repeater {
                            model: root.catKeys
                            delegate: Item {
                                width:160; height:34
                                property bool isActive: root.currentCat === modelData

                                Rectangle {
                                    anchors.fill:parent
                                    color: parent.isActive ? root.ink : (catMA.containsMouse ? Qt.rgba(70/255,63/255,46/255,0.07) : "transparent")
                                    Behavior on color { ColorAnimation { duration:150 } }
                                }
                                Row {
                                    anchors { left:parent.left; leftMargin:22; verticalCenter:parent.verticalCenter }
                                    spacing:8
                                    Rectangle {
                                        anchors.verticalCenter:parent.verticalCenter
                                        width: catMA.containsMouse || parent.parent.isActive ? 10 : 4; height:1
                                        color: parent.parent.isActive ? root.paper : root.inkSoft
                                        Behavior on width { NumberAnimation { duration:200; easing.type:Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration:150 } }
                                    }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text: root.catLabels[modelData] || modelData.toUpperCase()
                                        font.pixelSize:10; font.letterSpacing:2
                                        color: parent.parent.isActive ? root.paper : (catMA.containsMouse ? root.inkStrong : root.inkSoft)
                                        Behavior on color { ColorAnimation { duration:150 } }
                                    }
                                }
                                Text {
                                    anchors { right:parent.right; rightMargin:12; verticalCenter:parent.verticalCenter }
                                    text: root.apps.filter(function(a){ return modelData==="all"||a.cat===modelData }).length.toString().padStart(2,"0")
                                    font.pixelSize:9; font.letterSpacing:1
                                    color: parent.isActive ? Qt.rgba(214/255,207/255,181/255,0.6) : Qt.rgba(122/255,115/255,88/255,0.5)
                                }
                                MouseArea { id:catMA; anchors.fill:parent; hoverEnabled:true
                                    onClicked: { root.currentCat=modelData; root.focusIdx=0; searchInput.forceActiveFocus() } }
                            }
                        }

                        Item {
                            width:160; height:48
                            Column {
                                anchors { left:parent.left; leftMargin:22; bottom:parent.bottom; bottomMargin:6 }
                                spacing:4
                                Text { text:root.filteredApps.length+"/"+root.apps.length+" NODES"; font.pixelSize:8; font.letterSpacing:2; color:root.inkSoft; opacity:0.6 }
                                Rectangle {
                                    width:72; height:2; color:root.lineSoft
                                    Rectangle {
                                        height:parent.height; color:root.accent
                                        SequentialAnimation on x { running:root.menuOpen; loops:Animation.Infinite
                                            NumberAnimation { from:0; to:44; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:44; to:0; duration:1400; easing.type:Easing.InOutSine } }
                                        SequentialAnimation on width { running:root.menuOpen; loops:Animation.Infinite
                                            NumberAnimation { from:10; to:28; duration:1400; easing.type:Easing.InOutSine }
                                            NumberAnimation { from:28; to:10; duration:1400; easing.type:Easing.InOutSine } }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right panel
                Item {
                    anchors { left:sidebar.right; right:parent.right; top:parent.top; bottom:parent.bottom }
                    Column {
                        anchors.fill:parent

                        // Search
                        Item {
                            width:parent.width; height:46
                            Row {
                                anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                                          leftMargin:24; rightMargin:24 }
                                spacing:10
                                Text { anchors.verticalCenter:parent.verticalCenter; text:"▸"; font.pixelSize:12; color:root.accent }
                                FocusScope {
                                    id:searchScope; width:parent.width-60; height:30
                                    anchors.verticalCenter:parent.verticalCenter
                                    focus: root.menuOpen

                                    TextInput {
                                        id:           searchInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.pixelSize:13; font.letterSpacing:0.5; font.weight:Font.Normal
                                        color:        root.inkStrong
                                        cursorVisible:activeFocus
                                        focus:        true
                                        selectByMouse:true
                                        text:         root.searchQuery

                                        onTextEdited: { root.searchQuery=text; root.focusIdx=0 }

                                        Keys.onEscapePressed: root.closeMenu()
                                        Keys.onUpPressed: {
                                            root.focusIdx=Math.max(0,root.focusIdx-1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onDownPressed: {
                                            root.focusIdx=Math.min(root.filteredApps.length-1,root.focusIdx+1)
                                            appList.positionViewAtIndex(root.focusIdx, ListView.Contain)
                                        }
                                        Keys.onReturnPressed: {
                                            var a=root.filteredApps[root.focusIdx]
                                            if(a) root.launchApp(a.desktopId)
                                        }

                                        Text {
                                            visible:parent.text===""
                                            anchors.verticalCenter:parent.verticalCenter
                                            text:"search application..."
                                            font.pixelSize:13; font.italic:true; font.weight:Font.Light
                                            color:root.inkSoft; opacity:0.5
                                        }
                                    }
                                }
                            }
                            Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
                        }

                        // List
                        ListView {
                            id:appList; width:parent.width; height:parent.parent.height-46
                            clip:true; model:root.filteredApps; keyNavigationEnabled:false

                            delegate: Item {
                                id:appDelegate; width:appList.width; height:46
                                property bool isFocused: index===root.focusIdx

                                Rectangle {
                                    anchors.fill:parent; color:root.ink
                                    opacity: appMA.containsMouse||parent.isFocused ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:120 } }
                                }
                                Rectangle {
                                    anchors { left:parent.left; top:parent.top; bottom:parent.bottom }
                                    width:2; color:root.accent
                                    opacity: appMA.containsMouse||parent.isFocused ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:120 } }
                                }
                                Rectangle {
                                    anchors.bottom:parent.bottom
                                    visible: index<root.filteredApps.length-1
                                    x:24; width:parent.width-48; height:1; color:root.lineSoft; opacity:0.5
                                }

                                Row {
                                    anchors {
                                        left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                                        leftMargin:  appMA.containsMouse||appDelegate.isFocused ? 32 : 24
                                        rightMargin: 24
                                    }
                                    spacing:14
                                    Behavior on anchors.leftMargin { NumberAnimation { duration:180; easing.type:Easing.OutQuart } }

                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:modelData.id; width:22; font.pixelSize:9; font.letterSpacing:1.5
                                        color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,0.5) : root.inkSoft
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }
                                    Rectangle {
                                        anchors.verticalCenter:parent.verticalCenter
                                        width:28; height:28; color:"transparent"
                                        border.color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,0.8) : root.ink
                                        border.width:1
                                        Behavior on border.color { ColorAnimation { duration:120 } }
                                        Text {
                                            anchors.centerIn:parent; text:modelData.icon; font.pixelSize:12
                                            color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,0.9) : root.ink
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter:parent.verticalCenter; spacing:2
                                        Text {
                                            text:modelData.name; font.pixelSize:12; font.letterSpacing:1.2; font.weight:Font.Medium
                                            color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,1) : root.ink
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                        Text {
                                            text:modelData.meta; font.pixelSize:9; font.letterSpacing:1.5
                                            color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,0.5) : root.inkSoft
                                            Behavior on color { ColorAnimation { duration:120 } }
                                        }
                                    }
                                    Item { width:appList.width-310; height:1 }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:(root.catLabels[modelData.cat]||modelData.cat).toUpperCase()
                                        font.pixelSize:9; font.letterSpacing:2
                                        color: appMA.containsMouse||appDelegate.isFocused ? Qt.rgba(214/255,207/255,181/255,0.4) : root.inkSoft
                                        Behavior on color { ColorAnimation { duration:120 } }
                                    }
                                    Text {
                                        anchors.verticalCenter:parent.verticalCenter
                                        text:"▸"; font.pixelSize:14; color:root.accent
                                        opacity: appMA.containsMouse||appDelegate.isFocused ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration:120 } }
                                    }
                                }

                                MouseArea {
                                    id:appMA; anchors.fill:parent; hoverEnabled:true
                                    onEntered: root.focusIdx=index
                                    onClicked: root.launchApp(modelData.desktopId)
                                }
                            }

                            Item {
                                visible: root.filteredApps.length===0 && root.appsLoaded
                                width:appList.width; height:60
                                Text { anchors.centerIn:parent; text:"▸ NO RESULTS"; font.pixelSize:10; font.letterSpacing:3; color:root.inkSoft; opacity:0.5 }
                            }
                        }
                    }
                }
            }

            // ── FOOTER ──
            Item {
                id:footer; anchors.bottom:parent.bottom; width:parent.width; height:44
                Rectangle { anchors.top:parent.top; width:parent.width; height:1; color:root.lineSoft }
                Row {
                    anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter
                              leftMargin:28; rightMargin:28 }
                    Row {
                        spacing:0
                        Repeater {
                            model:[
                                {l:"TERMINAL", cmd:"kitty"},
                                {l:"FILES",    cmd:"kitty -e yazi"},
                                {l:"LOCK",     cmd:"$HOME/.config/quickshell/lock.sh"},
                                {l:"SHUTDOWN", cmd:"systemctl poweroff", danger:true}
                            ]
                            delegate: Item {
                                height:44; width:faLbl.implicitWidth+24
                                Rectangle {
                                    visible:index>0
                                    anchors{left:parent.left;top:parent.top;bottom:parent.bottom}
                                    width:1; color:root.lineSoft
                                }
                                Text {
                                    id:faLbl; anchors.centerIn:parent
                                    text:modelData.l; font.pixelSize:9; font.letterSpacing:2.5
                                    color: faMA.containsMouse ? (modelData.danger===true ? root.accent : root.inkStrong) : root.inkSoft
                                    Behavior on color { ColorAnimation { duration:150 } }
                                }
                                Rectangle {
                                    anchors{bottom:parent.bottom;horizontalCenter:parent.horizontalCenter;bottomMargin:6}
                                    width:faMA.containsMouse?faLbl.implicitWidth:0; height:1; color:root.accent
                                    Behavior on width { NumberAnimation { duration:200; easing.type:Easing.OutQuart } }
                                }
                                MouseArea { id:faMA; anchors.fill:parent; hoverEnabled:true; onClicked:root.launch(modelData.cmd) }
                            }
                        }
                    }
                    Item { width:parent.width-380; height:1 }
                    Row {
                        spacing:14; anchors.verticalCenter:parent.verticalCenter
                        Repeater {
                            model:[["↑↓","NAV"],["↵","OPEN"],["ESC","CLOSE"]]
                            Row {
                                spacing:5; anchors.verticalCenter:parent.verticalCenter
                                Rectangle {
                                    width:kbdT.implicitWidth+8; height:16; color:"transparent"
                                    border.color:root.lineSoft; border.width:1
                                    Text { id:kbdT; anchors.centerIn:parent; text:modelData[0]; font.pixelSize:9; font.letterSpacing:1; color:root.ink }
                                }
                                Text { text:modelData[1]; anchors.verticalCenter:parent.verticalCenter; font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft }
                            }
                        }
                    }
                }
            }
        }

        // Wipe curtain — frère du contenu
        Rectangle {
            id:wipeCurtain
            anchors{top:parent.top;bottom:parent.bottom}
            color:"#c8b89a"; z:50; width:2; x:root.lw-2
        }
    }

    // ── ANIMATIONS WIPE ──
    SequentialAnimation {
        id: wipeReveal
        onStarted: {
            panelHost.visible = true
            panelHost.x       = (root.screenW - root.lw) / 2 + root.lw + 2
            wipeCurtain.x     = 0
            wipeCurtain.width = root.lw
        }
        NumberAnimation {
            target:panelHost; property:"x"
            from:(root.screenW-root.lw)/2+root.lw+2; to:(root.screenW-root.lw)/2
            duration:440; easing.type:Easing.OutExpo
        }
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     from:0;       to:root.lw-2; duration:340; easing.type:Easing.OutExpo }
            NumberAnimation { target:wipeCurtain; property:"width"; from:root.lw; to:2;         duration:340; easing.type:Easing.OutExpo }
        }
        onFinished: {
            wipeCurtain.width = 0
            scanAnim.start()
            focusTimer.attempts = 0
            focusTimer.restart()
        }
    }

    SequentialAnimation {
        id: wipeHide
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     from:root.lw-2; to:0;       duration:180; easing.type:Easing.InOutQuart }
            NumberAnimation { target:wipeCurtain; property:"width"; from:2;         to:root.lw; duration:180; easing.type:Easing.InOutQuart }
        }
        NumberAnimation {
            target:panelHost; property:"x"
            from:(root.screenW-root.lw)/2; to:(root.screenW-root.lw)/2+root.lw+2
            duration:340; easing.type:Easing.InExpo
        }
        onFinished: { panelHost.visible=false; root.wipeHideRunning=false }
    }

    // ── API ──
    function openMenu() {
        if (menuOpen) return
        menuOpen    = true
        searchQuery = ""
        focusIdx    = 0
        currentCat  = "all"
        // Sync TextInput text avec la property vide
        searchInput.text = ""
        if (!appsLoaded) desktopReader.running = true
        wipeHide.stop()
        wipeReveal.start()
    }

    function closeMenu() {
        if (!menuOpen) return
        menuOpen         = false
        wipeHideRunning  = true
        wipeReveal.stop()
        wipeHide.start()
    }
}
