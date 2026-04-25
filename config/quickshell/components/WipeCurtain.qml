import QtQuick

// WipeCurtain — rideau NieR identique au player HTML v4
// Le contenu mis DANS ce composant est clipé par l'animation
// Usage : WipeCurtain { id: wipe; anchors.fill: parent; Rectangle { ... } }

Item {
    id: root

    property color curtainColor:   "#c8b89a"
    property int   revealDuration: 650
    property int   hideDuration:   600

    signal revealFinished
    signal hideFinished

    // Clip sur tout le composant
    clip: true

    // ── CONTENU (ce qu'on met dedans) ──
    default property alias contentData: contentItem.data

    Item {
        id:           contentItem
        anchors.fill: parent
        // Le contenu est toujours là, c'est le clip du parent qui le masque
    }

    // ── RIDEAU (rectangle sépia qui balaie) ──
    Rectangle {
        id:     curtain
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        color:  root.curtainColor
        width:  2
        x:      root.width - 2   // démarre à droite
        z:      10
    }

    // ── REVEAL : rideau part de droite, couvre tout, se rétracte à gauche ──
    SequentialAnimation {
        id: revealAnim

        // Phase 1 — le rideau s'étend vers la gauche (couvre)
        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: root.width - 2; to: 0
                duration: Math.round(root.revealDuration * 0.35)
                easing.type: Easing.InOutQuart
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: 2; to: root.width
                duration: Math.round(root.revealDuration * 0.35)
                easing.type: Easing.InOutQuart
            }
        }

        // Phase 2 — le rideau se rétracte vers la gauche (révèle)
        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: 0; to: 0
                duration: Math.round(root.revealDuration * 0.65)
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: root.width; to: 0
                duration: Math.round(root.revealDuration * 0.65)
                easing.type: Easing.InOutQuart
            }
        }

        onFinished: {
            curtain.x     = 0
            curtain.width = 0
            root.revealFinished()
        }
    }

    // ── HIDE : rideau part de gauche, couvre tout, laisse un trait à droite ──
    SequentialAnimation {
        id: hideAnim

        // Phase 1 — le rideau s'étend depuis la gauche (couvre)
        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: 0; to: 0
                duration: Math.round(root.hideDuration * 0.4)
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: 0; to: root.width
                duration: Math.round(root.hideDuration * 0.4)
                easing.type: Easing.InOutQuart
            }
        }

        // Phase 2 — le rideau se rétracte vers la droite (cache)
        ParallelAnimation {
            NumberAnimation {
                target: curtain; property: "x"
                from: 0; to: root.width - 2
                duration: Math.round(root.hideDuration * 0.6)
                easing.type: Easing.InOutQuart
            }
            NumberAnimation {
                target: curtain; property: "width"
                from: root.width; to: 2
                duration: Math.round(root.hideDuration * 0.6)
                easing.type: Easing.InOutQuart
            }
        }

        onFinished: {
            curtain.x     = root.width - 2
            curtain.width = 2
            root.hideFinished()
        }
    }

    function reveal() {
        hideAnim.stop()
        curtain.x     = root.width - 2
        curtain.width = 2
        revealAnim.start()
    }

    function hide() {
        revealAnim.stop()
        curtain.x     = 0
        curtain.width = 0
        hideAnim.start()
    }
}
