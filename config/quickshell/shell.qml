import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "widgets"
import "components"
import "settings"

ShellRoot {
    id: root

    // ── NOTIFICATIONS ──
    Notifications {}


    // ── VOLUMEBAR ──
    VolumeBar {}

    // ── PLAYERCTL ──
    property bool   playerVisible: false
    property bool   playerOnTop:   false
    property string mpTitle:    "END OF EVANGELION"
    property string mpArtist:   "NEON GENESIS // ANNO"
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   341

    Process {
        id: playerctlMeta
        command: ["playerctl","metadata","--format",
                  "{{title}}|{{artist}}|{{mpris:artUrl}}|{{status}}|{{position}}|{{mpris:length}}"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split("|")
                if (p.length >= 4) {
                    if (p[0]) root.mpTitle    = p[0]
                    if (p[1]) root.mpArtist   = p[1]
                    root.mpCoverUrl = p[2] || ""
                    root.mpPlaying  = (p[3] === "Playing")
                    root.mpPosition = parseFloat(p[4] || "0") / 1000000
                    root.mpLength   = Math.max(1, parseFloat(p[5] || "341000000") / 1000000)
                }
            }
        }
    }
    Process { id: pcPlay; command: ["playerctl","play-pause"]; running: false }
    Process { id: pcNext; command: ["playerctl","next"];       running: false }
    Process { id: pcPrev; command: ["playerctl","previous"];   running: false }
    Timer { interval:1000; running:true; repeat:true; onTriggered: playerctlMeta.running=true }

    property string currentUser: "user"
    Process {
        id: getUserProc; command:["sh","-c","echo $USER"]; running:true
        stdout: SplitParser { onRead: data => { var u=data.trim(); if(u!=="") root.currentUser=u } }
    }

    property int _lastToggle: 0; property int _lastFront: 0
    property int _lastMenu:   0

    Process { id:chkToggle; command:["sh","-c","wc -l < /tmp/qs-toggle 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastToggle){root._lastToggle=n;root.playerVisible=!root.playerVisible} }}
    }
    Process { id:chkFront; command:["sh","-c","wc -l < /tmp/qs-front 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastFront){root._lastFront=n;root.playerOnTop=!root.playerOnTop} }}
    }
    Process { id:chkMenu; command:["sh","-c","wc -l < /tmp/qs-menu 2>/dev/null || echo 0"]; running:false
        stdout:StdioCollector{ onStreamFinished:{ var n=parseInt(this.text.trim())||0; if(n!==root._lastMenu){root._lastMenu=n;detectMonitor.running=true} }}
    }

    Timer { interval:200; running:true; repeat:true
        onTriggered:{ chkToggle.running=true;chkFront.running=true;chkMenu.running=true }
    }

    Component.onCompleted: {
        Qt.createQmlObject(
            'import Quickshell.Io; Process{command:["sh","-c","rm -f /tmp/qs-menu /tmp/qs-toggle /tmp/qs-front"];running:true}',
            root, "cleanup")
    }

    property string menuActiveMonitor: Quickshell.screens.length>0 ? Quickshell.screens[0].name : ""
    signal menuFireToggle()

    Process {
        id: detectMonitor
        command: ["/bin/sh", Qt.resolvedUrl("active-monitor.sh").toString().replace("file://","")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var name = this.text.trim()
                if (name !== "") root.menuActiveMonitor = name
                root.menuFireToggle()
            }
        }
    }






    // ── MENU ──
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen:modelData
            anchors.top:true;anchors.left:true;anchors.right:true;anchors.bottom:true
            exclusionMode:ExclusionMode.Ignore
            aboveWindows:menuItem.menuOpen||menuItem.wipeHideRunning
            color:"transparent"
            WlrLayershell.keyboardFocus:menuItem.menuOpen?WlrKeyboardFocus.Exclusive:WlrKeyboardFocus.None
            implicitWidth:modelData.width;implicitHeight:modelData.height
            Menu{id:menuItem;anchors.fill:parent;screenW:modelData.width;screenH:modelData.height}
            Connections{target:root;function onMenuFireToggle(){
                if(root.menuActiveMonitor!==modelData.name)return
                if(menuItem.menuOpen)menuItem.closeMenu();else menuItem.openMenu()
            }}
        }
    }


    // ── PLAYER ──
    Variants {
        model:Quickshell.screens
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.top:true;anchors.right:true
            margins.top:Math.round(modelData.height*Settings.playerPositionY);margins.right:20
            exclusionMode:ExclusionMode.Ignore;aboveWindows:root.playerOnTop;color:"transparent"
            implicitWidth:Settings.playerWidth;implicitHeight:playerItem.implicitHeight
            Player{id:playerItem;anchors.fill:parent
                mpTitle:root.mpTitle;mpArtist:root.mpArtist;mpCoverUrl:root.mpCoverUrl
                mpPlaying:root.mpPlaying;mpPosition:root.mpPosition;mpLength:root.mpLength
                onPlayPause:pcPlay.running=true;onNextTrack:pcNext.running=true;onPrevTrack:pcPrev.running=true}
            Connections{target:root;function onPlayerVisibleChanged(){playerItem.toggleVisible()}}
        }
    }

    // ── COMPANIONS ──
    Variants {
        model:Quickshell.screens
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.bottom:true;anchors.right:true;margins.right:Settings.companionsMarginRight
            exclusionMode:ExclusionMode.Ignore;color:"transparent"
            implicitWidth:Settings.companionsSpriteSize+58;implicitHeight:compItem.implicitHeight
            Companions{id:compItem;anchors.fill:parent}
        }
    }
}
