import QtQuick

// Overlay scanlines NieR — à poser par-dessus n'importe quel widget
// Usage :
//   Scanlines { anchors.fill: parent }

Item {
    id:              root
    anchors.fill:    parent
    property real   lineOpacity: 0.06
    property int    lineSpacing: 3    // px entre chaque ligne
    property bool   grain:       true // grain de texture en plus

    // Ne capte aucun événement
    enabled:         false

    // Scanlines via Canvas (plus léger qu'un Repeater de rectangles)
    Canvas {
        id:           cv
        anchors.fill: parent
        opacity:      1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "rgba(0,0,0," + root.lineOpacity + ")"
            for (var y = 0; y < height; y += root.lineSpacing + 1) {
                ctx.fillRect(0, y, width, 1)
            }
        }

        // Redessine si la taille change
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()

        Component.onCompleted: requestPaint()
    }

    // Grain subtil (points aléatoires semi-transparents)
    Canvas {
        id:           grainCv
        anchors.fill: parent
        visible:      root.grain
        opacity:      0.35

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            // Grain léger : 1 pixel tous les ~8px²
            var density = Math.floor(width * height / 8)
            for (var i = 0; i < density; i++) {
                var x = Math.floor(Math.random() * width)
                var y = Math.floor(Math.random() * height)
                var a = Math.random() * 0.12
                ctx.fillStyle = "rgba(200,184,154," + a + ")"
                ctx.fillRect(x, y, 1, 1)
            }
        }

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
