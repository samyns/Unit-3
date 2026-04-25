import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ── État partagé ──
    property bool   revealing: false   // vidéo reveal en cours
    property bool   frozen:    false   // reveal freezée sur dernière frame
    property bool   hiding:    false   // vidéo hide en cours
    property bool   done:      false   // tout terminé

    // ── Paths génériques (portables) ──
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")

    // ── Auth partagée ──
    property string lockInput:   ""
    property bool   lockError:   false
    property bool   lockPending: false

    property string currentUser: "user"
    Process {
        id: getUserProc; command:["sh","-c","echo $USER"]; running:true
        stdout: SplitParser { onRead: data => { var u=data.trim(); if(u!=="") root.currentUser=u } }
    }

    Process {
        id: authProc
        command:["/bin/bash","-c",
            "printf '%s\\n' \"$LOCKPWD\" | pamtester qs-lock \"$LOCKUSER\" authenticate >/dev/null 2>&1 && echo OK || echo FAIL"]
        running: false
        property string envPwd:""; property string envUser:""
        environment:({"LOCKPWD":authProc.envPwd,"LOCKUSER":authProc.envUser})
        stdout: StdioCollector { onStreamFinished: {
            root.lockPending = false
            if (this.text.trim() === "OK") {
                root.lockInput = ""
                root.lockError = false
                root.doHide()   // auth OK → lancer hide
            } else {
                root.lockError = true
                root.lockInput = ""
                errTimer.restart()
            }
        }}
    }
    Timer { id:errTimer; interval:800; repeat:false; onTriggered: root.lockError=false }

    function doAuth() {
        if (root.lockPending || root.lockInput === "") return
        root.lockPending = true
        authProc.envPwd  = root.lockInput
        authProc.envUser = root.currentUser
        authProc.running = true
    }

    function doHide() {
        root.hiding = true
    }

    // ── Gestion du curseur Hyprland ──
    // Le curseur natif Hyprland est conservé, rien à faire côté lockscreen.

    Component.onCompleted: {
        root.revealing = true
    }

    // ── Screens ──
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
            WlrLayershell.keyboardFocus: (root.frozen && !root.hiding && !root.done)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property bool isPrimary: modelData.name === Quickshell.screens[0].name

            // ── Reveal ──
            MediaPlayer {
                id: reveal
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_reveal.mp4"
                videoOutput: voReveal
                audioOutput: null
                loops: 1
                autoPlay: false
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
                visible: !root.done  // toujours visible sauf après hide terminé
            }

            // ── Hide ──
            MediaPlayer {
                id: hide
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_hide.mp4"
                videoOutput: voHide
                audioOutput: null
                loops: 1
                autoPlay: false
                onMediaStatusChanged: function() {
                    // Fermeture gérée par hideFadeAnim.onFinished
                }
            }
            VideoOutput {
                id: voHide
                anchors.fill: parent
                z: 1
                visible: root.hiding || root.done
                opacity: 1.0
            }

            // Fade + fermeture 1s avant la fin de hide
            Timer {
                id: hideFadeTimer
                interval: 800   // 0.8s après le début de hide → fade sur les 400ms restantes
                repeat: false
                onTriggered: hideFadeAnim.start()
            }
            NumberAnimation {
                id: hideFadeAnim
                target: voHide; property: "opacity"
                from: 1.0; to: 0.0
                duration: 400
                easing.type: Easing.InQuad
                onFinished: {
                    root.done = true
                    exitTimer.restart()
                }
            }

            // ── UI Lockscreen ──
            Item {
                anchors.fill: parent
                // Toujours présent — opacity gère la visibilité pour les animations
                visible: !root.done
                z: 2

                // Fond sombre sur les coins
                property real uiOp: (root.frozen || root.revealing) ? 1 : 0
                Behavior on uiOp { NumberAnimation { duration: 400 } }

                // Coins
                Item {
                    anchors { top:parent.top; left:parent.left; topMargin:28; leftMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Row { spacing:5
                            Rectangle { width:5;height:5;radius:3;color:"#6e2a2a"
                                anchors.verticalCenter:parent.verticalCenter
                                SequentialAnimation on opacity { running:root.frozen; loops:Animation.Infinite
                                    NumberAnimation{to:0.3;duration:900} NumberAnimation{to:1;duration:900} }
                            }
                            Text{text:"SESSION LOCKED";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        }
                        Text{text:"NODE · "+root.currentUser+"@arch";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        Text{text:"セッションロック中";font.family:"Noto Sans JP";font.pixelSize:8;color:"#463f2e";opacity:0.7}
                    }
                }
                Item {
                    anchors { top:parent.top; right:parent.right; topMargin:28; rightMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Text{text:root.clockFull;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:200;horizontalAlignment:Text.AlignRight}
                        Text{text:"LONGVIC · FR";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:200;horizontalAlignment:Text.AlignRight}
                    }
                }
                Item {
                    anchors { bottom:parent.bottom; left:parent.left; bottomMargin:28; leftMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Text{text:"KERNEL 6.13.2";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        Text{text:"WM · hyprland";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                    }
                }
                Item {
                    anchors { bottom:parent.bottom; right:parent.right; bottomMargin:28; rightMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Text{text:"ARCH LINUX · RX 6700 XT";font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:220;horizontalAlignment:Text.AlignRight}
                    }
                }

                // Ticker
                Item {
                    anchors{bottom:parent.bottom;bottomMargin:65;left:parent.left;right:parent.right}
                    height:18;z:5;opacity:parent.uiOp;clip:true
                    Text {
                        id:tickTxt
                        text:"SYSTEM SCAN · OK ▸ MEMORY INTEGRITY · VERIFIED ▸ SESSION LOCKED · SECURE ▸ NETWORK UPLINK · STABLE ▸ THERMAL · NOMINAL ▸ AUTH DAEMON · LISTENING ▸ "
                        font.family:"Share Tech Mono";font.pixelSize:8;font.letterSpacing:3;color:"#463f2e";y:2
                        NumberAnimation on x { from:modelData.width; to:-tickTxt.implicitWidth; duration:55000; loops:Animation.Infinite; running:root.frozen }
                    }
                }

                // Panel central — slide depuis le haut
                Item {
                    id: panelHost
                    width: 380
                    height: panelRect.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    z: 6
                    opacity: 0

                    // Animation d'entrée
                    SequentialAnimation {
                        id: panelReveal
                        PropertyAction{target:panelHost;property:"anchors.verticalCenterOffset";value:-200}
                        PropertyAction{target:panelHost;property:"opacity";value:0}
                        PropertyAction{target:wipeScale;property:"yScale";value:1}
                        ParallelAnimation {
                            NumberAnimation{target:panelHost;property:"anchors.verticalCenterOffset";to:0;duration:580;easing.type:Easing.OutExpo}
                            NumberAnimation{target:panelHost;property:"opacity";to:1;duration:320}
                        }
                        NumberAnimation{target:wipeScale;property:"yScale";to:0;duration:460;easing.type:Easing.OutExpo}
                        onFinished: {
                            if (isPrimary) {
                                pwInput.forceActiveFocus()
                                focusRetry.restart()
                            }
                        }
                    }

                    // Animation de sortie
                    SequentialAnimation {
                        id: panelHide
                        NumberAnimation{target:wipeScale;property:"yScale";from:0;to:1;duration:210;easing.type:Easing.InQuart}
                        ParallelAnimation{
                            NumberAnimation{target:panelHost;property:"anchors.verticalCenterOffset";to:-200;duration:360;easing.type:Easing.InExpo}
                            NumberAnimation{target:panelHost;property:"opacity";to:0;duration:280}
                        }
                    }

                    // Shake
                    SequentialAnimation { id:shakeAnim
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";from:0;to:-10;duration:55}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:10;duration:75}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:-7;duration:65}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:7;duration:65}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:0;duration:55}
                    }

                    Rectangle {
                        id: panelRect
                        width:380; color:"#d6cfb5"
                        height: panelCol.implicitHeight + 72
                        border.color:"#463f2e"; border.width:1

                        // Grille fine
                        Repeater { model:20; Rectangle{x:index*20;y:0;width:1;height:panelRect.height;color:Qt.rgba(70/255,63/255,46/255,0.06)} }
                        Repeater { model:Math.ceil(panelRect.height/20); Rectangle{x:0;y:index*20;width:panelRect.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.06)} }

                        // Scan line
                        Rectangle {
                            x:0;width:parent.width;height:1;z:20
                            gradient:Gradient{ orientation:Gradient.Horizontal
                                GradientStop{position:0;color:"transparent"}
                                GradientStop{position:0.5;color:"#6e2a2a"}
                                GradientStop{position:1;color:"transparent"} }
                            SequentialAnimation on y {
                                running:root.frozen;loops:Animation.Infinite
                                NumberAnimation{from:0;to:panelRect.height;duration:3500;easing.type:Easing.Linear}
                                PauseAnimation{duration:600}
                            }
                        }

                        // Wipe curtain
                        Rectangle {
                            id:wipeCurtain;anchors.fill:parent;color:"#c8b89a";z:50
                            transform:Scale{id:wipeScale;xScale:1;yScale:1;origin.x:0;origin.y:0}
                        }

                        Column {
                            id: panelCol
                            width:308
                            anchors{top:parent.top;topMargin:36;horizontalCenter:parent.horizontalCenter}
                            spacing:0

                            // Avatar
                            Item { width:parent.width;height:90
                                Rectangle{width:76;height:76;border.color:"#463f2e";border.width:1;color:"transparent"
                                    anchors.horizontalCenter:parent.horizontalCenter
                                    Rectangle{width:52;height:52;color:"#463f2e";anchors.centerIn:parent
                                        transform:Rotation{angle:45;origin.x:26;origin.y:26}}
                                    Text{text:"NR";font.family:"Share Tech Mono";font.pixelSize:7;color:"#7a7358";opacity:0.5;anchors.top:parent.top;anchors.left:parent.left;anchors.margins:3}
                                    Text{text:"2B";font.family:"Share Tech Mono";font.pixelSize:7;color:"#7a7358";opacity:0.5;anchors.bottom:parent.bottom;anchors.right:parent.right;anchors.margins:3}
                                }
                            }
                            Text{text:root.currentUser.toUpperCase();font.family:"Share Tech Mono";font.pixelSize:13;font.letterSpacing:3;color:"#463f2e";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:4}
                            Text{text:"ユニット · アクティブ";font.family:"Noto Sans JP";font.pixelSize:8;color:"#7a7358";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:20}
                            Text{text:root.clockStr;font.family:"Share Tech Mono";font.pixelSize:46;font.letterSpacing:2;color:"#463f2e";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:6}
                            Text{text:root.dateStr;font.family:"Share Tech Mono";font.pixelSize:9;font.letterSpacing:3;color:"#7a7358";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:20}
                            Rectangle{width:parent.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.22)}
                            Item{width:1;height:22}

                            // Input
                            Item { width:parent.width;height:40
                                Rectangle{anchors.fill:parent;color:"transparent"
                                    border.color:inputScope.activeFocus?"#463f2e":Qt.rgba(70/255,63/255,46/255,0.22);border.width:1
                                    Behavior on border.color{ColorAnimation{duration:200}}}
                                Text{anchors.left:parent.left;anchors.leftMargin:10;anchors.verticalCenter:parent.verticalCenter;text:"▸";font.pixelSize:10;color:"#6e2a2a"}
                                FocusScope {
                                    id:inputScope
                                    anchors{fill:parent;leftMargin:26;rightMargin:10}
                                    focus: root.frozen
                                    TextInput {
                                        id:pwInput;anchors.fill:parent
                                        verticalAlignment:TextInput.AlignVCenter
                                        font.family:"Share Tech Mono";font.pixelSize:12;font.letterSpacing:2
                                        color:"#463f2e";echoMode:TextInput.Password;passwordCharacter:"·"
                                        focus:true;readOnly:false
                                        text:root.lockInput
                                        onTextEdited: { root.lockInput=text }
                                        Keys.onReturnPressed: { root.doAuth() }
                                        Keys.onEscapePressed: { root.lockInput="" }
                                        Text{visible:parent.text==="";anchors.verticalCenter:parent.verticalCenter
                                            text:"mot de passe...";font.family:"Share Tech Mono";font.pixelSize:11;font.italic:true;color:"#7a7358";opacity:0.5}
                                    }
                                }
                            }
                            Item{width:1;height:8}

                            // Dots
                            Row{anchors.horizontalCenter:parent.horizontalCenter;spacing:6
                                Repeater{model:6;Rectangle{width:6;height:6;color:"transparent";border.color:"#7a7358";border.width:1
                                    Rectangle{visible:index<root.lockInput.length;anchors.fill:parent;color:"#463f2e"}}}}
                            Item{width:1;height:6}

                            // Erreur
                            Text{text:"AUTHENTIFICATION ÉCHOUÉE";font.family:"Share Tech Mono";font.pixelSize:8;font.letterSpacing:2;color:"#6e2a2a"
                                anchors.horizontalCenter:parent.horizontalCenter
                                opacity:root.lockError?1:0;height:14;Behavior on opacity{NumberAnimation{duration:200}}}
                            Item{width:1;height:10}

                            // Bouton déverrouiller
                            Item{width:parent.width;height:42
                                Rectangle{anchors.fill:parent;color:"transparent";border.color:"#463f2e";border.width:1}
                                Rectangle{id:unlockFill;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#463f2e";width:0
                                    Behavior on width{NumberAnimation{duration:280;easing.type:Easing.InOutQuart}}}
                                Text{anchors.centerIn:parent;text:"DÉVERROUILLER";font.family:"Share Tech Mono";font.pixelSize:10;font.letterSpacing:3
                                    color:unlockMA.containsMouse?"#d6cfb5":"#463f2e";Behavior on color{ColorAnimation{duration:200}}}
                                MouseArea{id:unlockMA;anchors.fill:parent;hoverEnabled:true
                                    onEntered:unlockFill.width=parent.width;onExited:unlockFill.width=0
                                    onClicked:root.doAuth()}
                            }
                        }
                    }
                }

                Timer{id:focusRetry;interval:50;repeat:true;property int cnt:0
                    onTriggered:{pwInput.forceActiveFocus();if(++cnt>=8){running=false;cnt=0}}}

            // Rectangle noir de sécurité — couvre tout pendant les dernières frames
            Rectangle {
                anchors.fill: parent
                color: "black"
                z: 10
                visible: root.done
            }

            Timer {
                id: exitTimer; interval: 50; repeat: false
                onTriggered: Qt.quit()
            }


            }

            // Déclencher animations selon état
            Connections {
                target: root
                function onFrozenChanged() {
                }
                function onHidingChanged() {
                    if (root.hiding) {
                        reveal.stop()   // stopper reveal définitivement
                        panelHide.start()
                        hide.position = 0
                        hide.play()
                        if (isPrimary) hideFadeTimer.restart()
                    }
                }
                function onRevealingChanged() {
                    if (root.revealing) {
                        root.frozen = true  // activer le focus dès maintenant
                        reveal.position = 0
                        reveal.play()
                        panelOpenTimer.restart()
                    }
                }
                function onLockErrorChanged() {
                    if (root.lockError) shakeAnim.restart()
                }
            }

            Timer{id:panelOpenTimer;interval:100;repeat:false;onTriggered:panelReveal.start()}



            Component.onCompleted: {
                reveal.position = 0
                reveal.play()
            }
        }
    }

    // Horloge
    property string clockStr:  "--:--"
    property string dateStr:   "---- / -- / --"
    property string clockFull: "--:--:--"
    Timer {
        interval:1000;running:true;repeat:true
        onTriggered:{
            var d=new Date(),p=function(x){return String(x).padStart(2,"0")}
            root.clockStr  = p(d.getHours())+":"+p(d.getMinutes())
            root.clockFull = p(d.getHours())+":"+p(d.getMinutes())+":"+p(d.getSeconds())
            root.dateStr   = d.getFullYear()+" / "+p(d.getMonth()+1)+" / "+p(d.getDate())
        }
    }
}
