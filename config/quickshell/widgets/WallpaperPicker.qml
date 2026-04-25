import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ── État partagé ──
    property bool   revealing: false
    property bool   frozen:    false
    property bool   hiding:    false
    property bool   done:      false

    // ── Wallpapers ──
    property var    wallpapers:    []
    property int    currentIndex:  0
    // Chemin générique : $HOME/Pictures/wallpapers (ou XDG_PICTURES_DIR si défini)
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    property string xdgPictures:   Quickshell.env("XDG_PICTURES_DIR") || (home + "/Pictures")
    property string wallpaperDir:  xdgPictures + "/wallpapers"
    property string activeMonitor: ""   // nom du monitor actif (où est la souris)

    // ── Détecter le monitor actif ──
    Process {
        id: getMonitorProc
        command: ["sh","-c","hyprctl cursorpos -j | python3 -c \"\nimport sys,json,subprocess\npos=json.load(sys.stdin)\nmons=json.loads(subprocess.check_output(['hyprctl','monitors','-j']))\nfor m in mons:\n    x,y=m['x'],m['y']\n    w,h=m['width'],m['height']\n    if x<=pos['x']<x+w and y<=pos['y']<y+h:\n        print(m['name'])\n        break\n\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var n = this.text.trim()
                if (n !== "") root.activeMonitor = n
                root.revealing = true
            }
        }
    }

    // ── Lister les wallpapers ──
    Process {
        id: listWallpapers
        command: ["sh","-c","ls " + root.wallpaperDir + " | grep -iE '\\.(jpg|jpeg|png|webp)$'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var files = this.text.trim().split("\n").filter(function(f){ return f !== "" })
                root.wallpapers = files
            }
        }
    }

    // ── Appliquer le wallpaper ──
    function applyWallpaper(idx, monitor) {
        if (root.wallpapers.length === 0) return
        var file = root.wallpaperDir + "/" + root.wallpapers[idx]
        var cmd = monitor === "both"
            ? "awww img " + file
            : "awww img --outputs " + monitor + " " + file
        applyProc.command = ["sh","-c", cmd]
        applyProc.running = true
    }

    Process {
        id: applyProc
        command: ["sh","-c","echo noop"]
        running: false
    }

    // ── Gestion du curseur Hyprland ──
    // Le curseur natif Hyprland reste visible en permanence : on ne touche
    // ni à cursor:invisible avant ni à la fermeture.

    // Horloge
    property string clockFull: "--:--:--"
    Timer {
        interval:1000;running:true;repeat:true
        onTriggered:{
            var d=new Date(),p=function(x){return String(x).padStart(2,"0")}
            root.clockFull=p(d.getHours())+":"+p(d.getMinutes())+":"+p(d.getSeconds())
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top:true;anchors.left:true;anchors.right:true;anchors.bottom:true
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            implicitWidth: modelData.width; implicitHeight: modelData.height
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.frozen && !root.hiding && !root.done
                                          && modelData.name === root.activeMonitor)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property bool isPrimary: modelData.name === root.activeMonitor
            property bool isActive:  modelData.name === root.activeMonitor

            // ── Vidéo reveal ──
            MediaPlayer {
                id: reveal
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_reveal.mp4"
                videoOutput: voReveal
                audioOutput: null
                loops: 1; autoPlay: false
                onPositionChanged: function() {
                    if (root.hiding || root.done) return
                    var pos = reveal.position
                    var dur = reveal.duration
                    if (dur > 0 && pos >= dur - 34) {
                        reveal.pause()
                        root.revealing = false
                    }
                }
            }
            VideoOutput {
                id: voReveal
                anchors.fill: parent
                visible: !root.done
            }

            // ── Vidéo hide ──
            MediaPlayer {
                id: hide
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_hide.mp4"
                videoOutput: voHide
                audioOutput: null
                loops: 1; autoPlay: false
            }
            VideoOutput {
                id: voHide
                anchors.fill: parent; z:1
                visible: root.hiding || root.done
                opacity: 1.0
            }

            Timer {
                id: hideFadeTimer; interval:800; repeat:false
                onTriggered: hideFadeAnim.start()
            }
            NumberAnimation {
                id: hideFadeAnim
                target: voHide; property: "opacity"
                from:1.0; to:0.0; duration:250
                easing.type: Easing.InQuad
                onFinished: { root.done=true; exitTimer.restart() }
            }
            Timer { id:exitTimer; interval:50; repeat:false
                onTriggered: Qt.quit()
            }
            Rectangle { anchors.fill:parent; color:"black"; z:10; visible:root.done }

            // ── UI — seulement sur l'écran actif ──
            Item {
                anchors.fill: parent
                visible: !root.done && isActive
                z: 2

                property real uiOp: (root.frozen || root.revealing) ? 1 : 0
                Behavior on uiOp { NumberAnimation { duration:400 } }

                // Scroll souris sur toute la surface
                MouseArea {
                    anchors.fill: parent
                    onWheel: function(e) {
                        root.navigate(e.angleDelta.y < 0 ? 1 : -1)
                    }
                }

                // Coins déco
                Item {
                    anchors{top:parent.top;left:parent.left;topMargin:28;leftMargin:30}
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Row { spacing:5
                            Rectangle { width:5;height:5;radius:3;color:"#6e2a2a"
                                anchors.verticalCenter:parent.verticalCenter
                                SequentialAnimation on opacity { running:root.frozen; loops:Animation.Infinite
                                    NumberAnimation{to:0.3;duration:900} NumberAnimation{to:1;duration:900} }
                            }
                            Text{text:"WALLPAPER SELECT";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        }
                        Text{text:"NODE · "+root.activeMonitor;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                    }
                }
                Item {
                    anchors{top:parent.top;right:parent.right;topMargin:28;rightMargin:30}
                    z:5; opacity:parent.uiOp
                    Text{text:root.clockFull;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                }
                Item {
                    anchors{bottom:parent.bottom;left:parent.left;bottomMargin:28;leftMargin:30}
                    z:5; opacity:parent.uiOp
                    Text{text:"↑↓ / SCROLL  NAVIGATE  ·  ESC  QUIT";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                }

                // ── Boutons apply — toujours visibles ──
                Item {
                    id: applyPanel
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 60
                    width: 420
                    height: applyCol.implicitHeight + 48
                    z: 7
                    opacity: root.frozen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration:300 } }

                    Rectangle {
                        anchors.fill: parent
                        color: "#d6cfb5"
                        border.color: "#463f2e"; border.width: 1

                        Repeater { model:22; Rectangle{x:index*20;y:0;width:1;height:parent.height;color:Qt.rgba(70/255,63/255,46/255,0.06)} }

                        Column {
                            id: applyCol
                            width: 348
                            anchors{top:parent.top;topMargin:20;horizontalCenter:parent.horizontalCenter}
                            spacing: 10

                            Text {
                                text: "APPLY WALLPAPER"
                                font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:3
                                color:"#463f2e";anchors.horizontalCenter:parent.horizontalCenter
                            }
                            Rectangle { width:parent.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.22) }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                // Bouton écran actif
                                Item { width:162; height:42
                                    Rectangle { anchors.fill:parent;color:"transparent";border.color:"#463f2e";border.width:1 }
                                    Rectangle { id:fill1;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#463f2e";width:0
                                        Behavior on width{NumberAnimation{duration:220}} }
                                    Text { anchors.centerIn:parent
                                        text:"THIS SCREEN"
                                        font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:2
                                        color:ma1.containsMouse?"#d6cfb5":"#463f2e"
                                        Behavior on color{ColorAnimation{duration:200}} }
                                    MouseArea { id:ma1;anchors.fill:parent;hoverEnabled:true
                                        onEntered:fill1.width=parent.width;onExited:fill1.width=0
                                        onClicked:{ root.applyWallpaper(root.currentIndex, root.activeMonitor); root.doClose() } }
                                }

                                // Bouton les deux écrans
                                Item { width:162; height:42
                                    Rectangle { anchors.fill:parent;color:"transparent";border.color:"#463f2e";border.width:1 }
                                    Rectangle { id:fill2;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#463f2e";width:0
                                        Behavior on width{NumberAnimation{duration:220}} }
                                    Text { anchors.centerIn:parent
                                        text:"ALL SCREENS"
                                        font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:2
                                        color:ma2.containsMouse?"#d6cfb5":"#463f2e"
                                        Behavior on color{ColorAnimation{duration:200}} }
                                    MouseArea { id:ma2;anchors.fill:parent;hoverEnabled:true
                                        onEntered:fill2.width=parent.width;onExited:fill2.width=0
                                        onClicked:{ root.applyWallpaper(root.currentIndex, "both"); root.doClose() } }
                                }
                            }
                        }
                    }
                }

                // ── Carrousel ──
                // ── Carrousel ──
                Item {
                    id: carousel
                    anchors.top: parent.top
                    anchors.topMargin: 80
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: parent.height - 220
                    z: 6
                    opacity: root.frozen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration:300 } }

                    focus: root.frozen && isActive
                    Keys.onEscapePressed: root.doClose()
                    Keys.onLeftPressed:   root.navigate(-1)
                    Keys.onRightPressed:  root.navigate(1)
                    Keys.onUpPressed:     root.navigate(-1)
                    Keys.onDownPressed:   root.navigate(1)

                    readonly property int n: root.wallpapers.length

                    // Dimensions de base (taille de la vignette centrale à pleine échelle)
                    readonly property int baseW: 800
                    readonly property int baseH: 500
                    // Ligne de base commune : toutes les vignettes ont leur bas aligné ici
                    readonly property int baselineY: height / 2 + baseH / 2

                    // Échelles par distance (slot) au centre
                    readonly property real scaleCenter: 1.0
                    readonly property real scaleNear:   0.54   // ~280/520
                    readonly property real scaleFar:    0.35   // ~180/520

                    // Espacements X (demi-axes entre centres de vignettes) par slot
                    readonly property int offsetNear: 280
                    readonly property int offsetFar:  576

                    // Une vignette par wallpaper. Chaque vignette choisit sa place
                    // en fonction de l'offset signé vers currentIndex (chemin le plus
                    // court sur la boucle). Position, scale et opacity sont animées
                    // -> le zoom est smooth et part du bas (transformOrigin: Bottom).
                    Repeater {
                        model: root.wallpapers

                        Item {
                            id: thumb
                            property int wIdx: index
                            // Offset signé (-n/2 .. n/2) = chemin le plus court vers currentIndex
                            property int rawDelta: carousel.n > 0 ? (wIdx - root.currentIndex) : 0
                            property int delta: {
                                if (carousel.n === 0) return 0
                                var d = rawDelta
                                var half = carousel.n / 2
                                if (d >  half) d -= carousel.n
                                if (d < -half) d += carousel.n
                                return d
                            }
                            property int absDelta: Math.abs(delta)

                            // Position X et échelle dérivées du slot
                            property real targetScale:
                                  absDelta === 0 ? carousel.scaleCenter
                                : absDelta === 1 ? carousel.scaleNear
                                :                  carousel.scaleFar
                            property real targetOpacity:
                                  absDelta === 0 ? 1.0
                                : absDelta === 1 ? 0.65
                                : absDelta === 2 ? 0.3
                                :                  0.0
                            property int targetOffsetX:
                                  absDelta === 0 ? 0
                                : absDelta === 1 ? (delta > 0 ?  carousel.offsetNear : -carousel.offsetNear)
                                :                  (delta > 0 ?  carousel.offsetFar  : -carousel.offsetFar)

                            width: carousel.baseW
                            height: carousel.baseH
                            x: carousel.width/2 + targetOffsetX - carousel.baseW/2
                            y: carousel.baselineY - carousel.baseH
                            scale: targetScale
                            opacity: targetOpacity
                            z: absDelta === 0 ? 10 : (3 - absDelta)
                            visible: absDelta <= 2
                            transformOrigin: Item.Bottom

                            // Animations fluides — le scale part du bas grâce au transformOrigin
                            Behavior on x       { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }
                            Behavior on scale   { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration:320; easing.type:Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                color: "#0f0d0a"
                                border.color: thumb.absDelta === 0 ? "#c8b89a" : "#463f2e"
                                border.width: thumb.absDelta === 0 ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration:260 } }

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: "file://" + root.wallpaperDir + "/" + root.wallpapers[thumb.wIdx]
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                }

                                // Bandeau avec le nom, visible seulement sur la vignette centrale
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 24
                                    color: Qt.rgba(0,0,0,0.6)
                                    opacity: thumb.absDelta === 0 ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration:200 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.wallpapers[thumb.wIdx]
                                        font.family: "Share Tech Mono"
                                        font.pixelSize: 8
                                        color: "#c8b89a"
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                // Clic sur une voisine -> on navigue vers elle
                                onClicked: if (thumb.delta !== 0) root.navigate(thumb.delta)
                                onWheel: function(e) { root.navigate(e.angleDelta.y < 0 ? 1 : -1) }
                            }
                        }
                    }
                }
            }

            // ── Connexions état ──
            Connections {
                target: root
                function onRevealingChanged() {
                    if (root.revealing) {
                        root.frozen = true
                        reveal.position = 0
                        reveal.play()
                        panelOpenTimer.restart()
                    }
                }
                function onHidingChanged() {
                    if (root.hiding) {
                        reveal.stop()
                        hide.position = 0
                        hide.play()
                        if (isPrimary) hideFadeTimer.restart()
                    }
                }
            }
            Timer { id:panelOpenTimer; interval:100; repeat:false; onTriggered: carousel.focus=true }
        }
    }

    // ── Navigation ──
    function navigate(dir) {
        var n = root.wallpapers.length
        if (n === 0) return
        root.currentIndex = ((root.currentIndex + dir) % n + n) % n
    }

    function doClose() {
        root.hiding = true
    }
}
