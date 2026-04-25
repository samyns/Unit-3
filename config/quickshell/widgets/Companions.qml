import QtQuick
import Quickshell
import "../settings"

Item {
    id: root

    readonly property var companions: [
        {
            name:  "AMAZON", color: "#c87060",
            src:   Qt.resolvedUrl("../assets/amazon.gif"),
            lines: [
                "Tu tapes vite. Pas aussi vite qu'une hache.",
                "Mon peuple n'a pas de pomodoro. On ne s'arrête pas.",
                "Ce timer est inutile. Travaille.",
                "Hmm. Bonne cadence. Continue.",
                "En bataille, on ne compte pas les secondes.",
                "Ma hache est plus précise que ton curseur.",
                "Tu appelles ça de la productivité ?",
                "Je n'ai pas besoin de pause. Toi peut-être."
            ],
            reactions: [
                { type: "angry",  text: "Arrête de me cliquer dessus ! Tu veux ma hache dans ton écran ?!" },
                { type: "angry",  text: "C'EST MON DERNIER AVERTISSEMENT." },
                { type: "bounce", text: "...D'accord. Tu gagnes. Je fais le saut. Content(e) ?" },
                { type: "angry",  text: "Si tu cliques encore une fois... je jure par ma hache..." }
            ]
        },
        {
            name:  "MAI SHIRANUI", color: "#c8a860",
            src:   Qt.resolvedUrl("../assets/mai.gif"),
            lines: [
                "Tu pourrais taper plus gracieusement.",
                "Ce n'est pas un timer, c'est une danse.",
                "Mon éventail est plus rapide que ta souris.",
                "Un peu plus d'élégance, s'il te plaît.",
                "La vitesse sans grâce, c'est du bruit.",
                "Tu travailles bien... pour quelqu'un sans éventail.",
                "Encore une session ? Prends soin de toi.",
                "Je préfère les fleurs aux terminaux."
            ],
            reactions: [
                { type: "love", text: "Oh... tu me remarques tant que ça ? *rougit*" },
                { type: "love", text: "M-mais... tu es vraiment adorable !" },
                { type: "spin", text: "Hihihi~ Je tourne pour toi !" },
                { type: "love", text: "...Je crois que je me suis attachée à toi." }
            ]
        },
        {
            name:  "2B // YoRHa", color: "#c8b89a",
            src:   Qt.resolvedUrl("../assets/2b.gif"),
            lines: [
                "Les émotions sont interdites. Pourtant... je veille.",
                "Mission en cours. Continuez à travailler.",
                "Système opérationnel. Anomalies : 0.",
                "Pod : aucune menace détectée. Pour l'instant.",
                "Nous combattons pour les humains. Même au clavier.",
                "接続中... システム正常。",
                "Ce timer compte chaque seconde. Comme moi.",
                "La gloire aux androïdes. Et à votre WPM."
            ],
            reactions: [
                { type: "glow", text: "Comportement d'opérateur anormal détecté. Je note." },
                { type: "glow", text: "Ce niveau d'interaction dépasse les paramètres normaux." },
                { type: "glow", text: "Les émotions sont interdites. Mais... ce geste me semble familier." },
                { type: "glow", text: "...Pod. Enregistre. L'opérateur me fait confiance." }
            ]
        }
    ]

    property int  currentIdx:       0
    property var  lineIdxs:         [0, 0, 0]
    property var  reactUsed:        [[], [], []]
    property var  clickTimes:       [[], [], []]
    property var  reactCooldown:    [0, 0, 0]
    property bool isReacting:       false
    property bool bubbleVisible:    false
    property bool isReactionBubble: false
    property string bubbleText_:    ""

    readonly property int spamCount:       7
    readonly property int spamWindow:      1200
    readonly property int reactCooldownMs: 4000
    readonly property int spriteSize:      Settings.companionsSpriteSize

    // Largeur fixe = flèches (26) + sprite (128) + flèches (26) + spacing (6)
    implicitWidth:  26 + 128 + 26 + 6
    implicitHeight: outerCol.implicitHeight

    // Tout dans une colonne simple, de haut en bas
    Column {
        id:      outerCol
        width:   root.implicitWidth
        anchors.bottom: parent.bottom
        anchors.right:  parent.right
        spacing: 4

        // ── BULLE ── hauteur fixe, clip interne
        Rectangle {
            id:      bubble
            width:   parent.width
            height:  86
            color:   Qt.rgba(11/255, 10/255, 9/255, 0.97)
            border.color: root.isReactionBubble ? "#c8a860" : Qt.rgba(200/255,184/255,154/255,0.22)
            border.width: 1
            visible: root.bubbleVisible
            opacity: root.bubbleVisible ? 1 : 0
            clip:    true
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 3

                Text {
                    width: parent.width
                    text:  root.companions[root.currentIdx].name
                    font.family: "Share Tech Mono"; font.pixelSize: 8; font.letterSpacing: 3
                    color: root.companions[root.currentIdx].color
                    elide: Text.ElideRight
                }
                Text {
                    width:    parent.width
                    text:     root.bubbleText_
                    font.family: "Share Tech Mono"; font.pixelSize: 9
                    color:    Qt.rgba(200/255,184/255,154/255,0.65)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide:    Text.ElideRight
                    lineHeight: 1.4
                }
            }
        }

        // ── CARROUSEL ──
        Row {
            width:   parent.width
            spacing: 3

            // Flèche gauche
            Rectangle {
                width: 26; height: 38; color: "transparent"
                border.color: Qt.rgba(200/255,184/255,154/255,0.15); border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 18
                       color: maL.containsMouse ? "#c8b89a" : Qt.rgba(200/255,184/255,154/255,0.35)
                       Behavior on color { ColorAnimation { duration: 100 } } }
                MouseArea { id: maL; anchors.fill: parent; hoverEnabled: true; onClicked: root.navigate(-1) }
            }

            // Sprite
            Item {
                width: root.spriteSize; height: root.spriteSize
                anchors.verticalCenter: parent.verticalCenter

                AnimatedImage {
                    id: sprite
                    width: root.spriteSize; height: root.spriteSize
                    source:   root.companions[root.currentIdx].src
                    playing:  true
                    smooth:   false
                    fillMode: Image.PreserveAspectFit

                    property real reactX:     0
                    property real reactScale: 1.0
                    x: reactX; scale: reactScale

                    SequentialAnimation {
                        id: angryAnim
                        NumberAnimation { target: sprite; property: "reactX"; to: -7; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to:  7; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to: -6; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to:  6; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to: -4; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to:  4; duration: 55 }
                        NumberAnimation { target: sprite; property: "reactX"; to:  0; duration: 55 }
                        onFinished: sprite.reactX = 0
                    }
                    SequentialAnimation {
                        id: loveAnim
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.18; duration: 120; easing.type: Easing.OutQuad }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.05; duration: 100 }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.12; duration: 100 }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.0;  duration: 180; easing.type: Easing.InQuad }
                        onFinished: sprite.reactScale = 1.0
                    }
                    SequentialAnimation {
                        id: bounceAnim
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.18; duration: 200; easing.type: Easing.OutQuad }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.0;  duration: 160; easing.type: Easing.InQuad }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.10; duration: 130 }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.0;  duration: 110 }
                        onFinished: sprite.reactScale = 1.0
                    }
                    SequentialAnimation {
                        id: glowAnim
                        NumberAnimation { target: sprite; property: "opacity"; to: 0.3; duration: 80 }
                        NumberAnimation { target: sprite; property: "opacity"; to: 1.0; duration: 130 }
                        NumberAnimation { target: sprite; property: "opacity"; to: 0.5; duration: 80 }
                        NumberAnimation { target: sprite; property: "opacity"; to: 1.0; duration: 220 }
                        onFinished: sprite.opacity = 1.0
                    }
                    SequentialAnimation {
                        id: spinAnim
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.12; duration: 100 }
                        NumberAnimation { target: sprite; property: "reactX"; to: 10;  duration: 100 }
                        NumberAnimation { target: sprite; property: "reactX"; to: -10; duration: 140 }
                        NumberAnimation { target: sprite; property: "reactX"; to: 0;   duration: 110 }
                        NumberAnimation { target: sprite; property: "reactScale"; to: 1.0; duration: 100 }
                        onFinished: { sprite.reactX = 0; sprite.reactScale = 1.0 }
                    }
                    NumberAnimation {
                        id: slideOut
                        target: sprite; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad
                        onFinished: { sprite.source = root.companions[root.currentIdx].src; slideIn.start() }
                    }
                    NumberAnimation {
                        id: slideIn
                        target: sprite; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.isReacting
                    onClicked: root.handleClick()
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // Flèche droite
            Rectangle {
                width: 26; height: 38; color: "transparent"
                border.color: Qt.rgba(200/255,184/255,154/255,0.15); border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "›"; font.pixelSize: 18
                       color: maR.containsMouse ? "#c8b89a" : Qt.rgba(200/255,184/255,154/255,0.35)
                       Behavior on color { ColorAnimation { duration: 100 } } }
                MouseArea { id: maR; anchors.fill: parent; hoverEnabled: true; onClicked: root.navigate(1) }
            }
        }

        // ── NOM ──
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  root.companions[root.currentIdx].name
            font.family: "Share Tech Mono"; font.pixelSize: 8; font.letterSpacing: 2
            color: root.companions[root.currentIdx].color
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // ── DOTS ──
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5
            Repeater {
                model: root.companions.length
                Rectangle {
                    width: 5; height: 5
                    color: index === root.currentIdx ? "#c8b89a" : Qt.rgba(200/255,184/255,154/255,0.15)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea { anchors.fill: parent
                        onClicked: if (index !== root.currentIdx) root.navigate(index > root.currentIdx ? 1 : -1) }
                }
            }
        }

        // ── BARRE SPAM ──
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Repeater {
                model: root.spamCount
                Rectangle {
                    width: 9; height: 3
                    property int recentCount: {
                        var now=Date.now(); var ct=root.clickTimes[root.currentIdx]; var cnt=0
                        for(var i=0;i<ct.length;i++) if(now-ct[i]<root.spamWindow) cnt++
                        return cnt
                    }
                    color: index < recentCount
                        ? (recentCount >= root.spamCount-1 ? "#c87060" : "#c8a860")
                        : Qt.rgba(200/255,184/255,154/255,0.1)
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
            }
        }
    }

    Timer { id: bubbleTimer; onTriggered: root.bubbleVisible = false }
    Timer { id: reactTimer; interval: 3500; onTriggered: root.isReacting = false }

    function navigate(dir) {
        bubbleVisible = false
        slideOut.start()
        currentIdx = (currentIdx + dir + companions.length) % companions.length
    }

    function handleClick() {
        if (root.isReacting) return
        var now=Date.now(); var ct=clickTimes[currentIdx].slice()
        ct.push(now); ct=ct.filter(function(t){return now-t<spamWindow})
        var ct2=clickTimes.slice(); ct2[currentIdx]=ct; clickTimes=ct2
        var cooldownOk=(now-reactCooldown[currentIdx])>reactCooldownMs

        if (ct.length >= spamCount && cooldownOk) {
            root.isReacting=true
            var cd=reactCooldown.slice(); cd[currentIdx]=now; reactCooldown=cd
            var ct3=clickTimes.slice(); ct3[currentIdx]=[]; clickTimes=ct3
            var used=reactUsed[currentIdx].slice()
            var reacts=companions[currentIdx].reactions
            var available=[]; for(var i=0;i<reacts.length;i++) if(used.indexOf(i)<0) available.push(i)
            var pickIdx
            if(available.length>0){pickIdx=available[Math.floor(Math.random()*available.length)];used.push(pickIdx)}
            else{pickIdx=Math.floor(Math.random()*reacts.length);used=[]}
            var ru=reactUsed.slice(); ru[currentIdx]=used; reactUsed=ru
            triggerReaction(reacts[pickIdx])
        } else {
            var li=lineIdxs.slice()
            var line=companions[currentIdx].lines[li[currentIdx]%companions[currentIdx].lines.length]
            li[currentIdx]++; lineIdxs=li
            showBubble(line, false)
        }
    }

    function triggerReaction(r) {
        showBubble(r.text, true)
        sprite.reactX=0; sprite.reactScale=1.0; sprite.opacity=1.0
        if(r.type==="angry") angryAnim.start()
        else if(r.type==="love") loveAnim.start()
        else if(r.type==="bounce") bounceAnim.start()
        else if(r.type==="glow") glowAnim.start()
        else if(r.type==="spin") spinAnim.start()
        reactTimer.restart()
    }

    function showBubble(text, isReaction) {
        bubbleText_=text; isReactionBubble=isReaction; bubbleVisible=true
        bubbleTimer.interval=isReaction?5500:4000; bubbleTimer.restart()
    }

    Component.onCompleted: Qt.callLater(function(){
        showBubble(companions[0].lines[0], false)
        var li=lineIdxs.slice(); li[0]=1; lineIdxs=li
    })
}
