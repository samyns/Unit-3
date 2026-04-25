import QtQuick

// Décorations de coins NieR — les 4 coins SVG cassette futurism
// Usage :
//   CornerDeco { anchors.fill: parent }

Item {
    id:           root
    anchors.fill: parent
    enabled:      false   // ne capte pas les événements

    property color  lineColor: Qt.rgba(200/255, 184/255, 154/255, 0.4)
    property int    size:      18    // px de chaque coin
    property real   lineWidth: 0.8

    // ── COIN HAUT-GAUCHE ──
    Canvas {
        id:     ctl
        x:      0; y: 0
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), false, false)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── COIN HAUT-DROIT ──
    Canvas {
        id:     ctr
        x:      parent.width - root.size; y: 0
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), true, false)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── COIN BAS-GAUCHE ──
    Canvas {
        id:     cbl
        x:      0; y: parent.height - root.size
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), false, true)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // ── COIN BAS-DROIT ──
    Canvas {
        id:     cbr
        x:      parent.width - root.size
        y:      parent.height - root.size
        width:  root.size; height: root.size
        onPaint: drawCorner(getContext("2d"), true, true)
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // Redessine tous les coins si la taille du parent change
    onWidthChanged:  { ctl.requestPaint(); ctr.requestPaint(); cbl.requestPaint(); cbr.requestPaint() }
    onHeightChanged: { ctl.requestPaint(); ctr.requestPaint(); cbl.requestPaint(); cbr.requestPaint() }

    // ── FONCTION DE DESSIN ──
    // flipH = true  → coin droit
    // flipV = true  → coin bas
    function drawCorner(ctx, flipH, flipV) {
        var w = root.size
        var h = root.size
        ctx.clearRect(0, 0, w, h)

        ctx.save()

        // Flip horizontal
        if (flipH) {
            ctx.translate(w, 0)
            ctx.scale(-1, 1)
        }
        // Flip vertical
        if (flipV) {
            ctx.translate(0, h)
            ctx.scale(1, -1)
        }

        var c = root.lineColor.toString()
        ctx.strokeStyle = c
        ctx.fillStyle   = c
        ctx.lineWidth   = root.lineWidth

        var seg = Math.round(w * 0.33)  // longueur des traits
        var dot = Math.round(w * 0.10)  // taille du point carré

        // Trait horizontal
        ctx.beginPath()
        ctx.moveTo(0, seg)
        ctx.lineTo(seg - dot * 0.5, seg)
        ctx.stroke()

        // Trait vertical
        ctx.beginPath()
        ctx.moveTo(seg, 0)
        ctx.lineTo(seg, seg - dot * 0.5)
        ctx.stroke()

        // Point carré à l'intersection
        ctx.fillRect(seg - dot * 0.5, seg - dot * 0.5, dot, dot)

        ctx.restore()
    }
}
