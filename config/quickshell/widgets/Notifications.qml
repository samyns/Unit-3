// notifications.qml
// Daemon de notifications style NieR / YoRHa
//
// Installation :
//   1. Tuer tout autre daemon : pkill dunst; pkill mako; pkill swaync
//   2. qs -p notifications.qml
//
// Tests :
//   notify-send "Test" "Ceci est une notification"
//   notify-send -u critical "ATTENTION" "Niveau critique"
//   notify-send -u low "Info" "Niveau bas"

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

Scope {
    id: root

    readonly property int topOffsetPercent: 6
    readonly property int leftMargin: 24
    readonly property int notifWidth: 360
    readonly property int notifSpacing: 10
    readonly property int defaultTimeout: 5000
    readonly property int criticalTimeout: 10000

    NotificationServer {
        id: notifServer

        actionsSupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        bodyHyperlinksSupported: false
        imageSupported: true
        keepOnReload: true

        onNotification: (n) => {
            n.tracked = true;
        }
    }

    readonly property var tracked: notifServer.trackedNotifications

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                left: true
                bottom: true
            }
            implicitWidth: root.notifWidth + root.leftMargin + 40
            color: "transparent"

            // ═══════════════════════════════════════════════════════════
            // MASQUE D'INPUT : ne capture les clics QUE dans la zone
            // qui entoure la pile de notifs. Quand il n'y en a aucune,
            // la région fait 0x0 → tout passe à travers.
            // ═══════════════════════════════════════════════════════════
            mask: Region {
                x: column.x
                y: column.y
                width: notifRepeater.count > 0 ? root.notifWidth : 0
                height: {
                    // Dépendance explicite pour forcer le recalcul
                    column.layoutTrigger;
                    let h = 0;
                    for (let i = 0; i < column.children.length; i++) {
                        const c = column.children[i];
                        if (c && c.isNotifItem === true && c.height > 0) {
                            h += c.height + root.notifSpacing;
                        }
                    }
                    return Math.max(0, h - root.notifSpacing);
                }
            }

            Item {
                id: column
                anchors.left: parent.left
                anchors.leftMargin: root.leftMargin
                anchors.top: parent.top
                anchors.topMargin: parent.height * root.topOffsetPercent / 100
                width: root.notifWidth
                height: parent.height - anchors.topMargin

                // Trigger pour forcer la re-évaluation du mask de la fenêtre
                property int layoutTrigger: 0

                Repeater {
                    id: notifRepeater
                    model: root.tracked

                    onItemAdded: column.layoutTrigger++
                    onItemRemoved: column.layoutTrigger++

                    delegate: NotifItem {
                        required property var modelData
                        required property int index

                        notification: modelData
                        width: root.notifWidth
                        itemIndex: index

                        onHeightChanged: column.layoutTrigger++
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    // Composant notif
    // ════════════════════════════════════════════════════════════════
    component NotifItem: Item {
        id: notif

        property var notification: null
        property int itemIndex: 0
        readonly property bool isNotifItem: true

        readonly property int urgency: notification ? notification.urgency : 1
        readonly property color accentColor: {
            if (urgency === 2) return "#6e2a2a";
            if (urgency === 0) return "#7a7358";
            return "#463f2e";
        }

        readonly property string urgencyLabel: {
            if (urgency === 2) return "CRITICAL";
            if (urgency === 0) return "INFO";
            return "NOTICE";
        }

        readonly property string urgencyJp: {
            if (urgency === 2) return "緊急";
            if (urgency === 0) return "情報";
            return "通知";
        }

        // Calcul de la position Y en sommant les hauteurs des frères précédents
        y: {
            let acc = 0;
            const parentItem = parent;
            if (!parentItem) return 0;
            for (let i = 0; i < parentItem.children.length; i++) {
                const c = parentItem.children[i];
                if (c === notif) break;
                if (c && c.isNotifItem === true) {
                    acc += c.height + root.notifSpacing;
                }
            }
            return acc;
        }

        Behavior on y {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        implicitHeight: card.implicitHeight
        height: implicitHeight

        state: "entering"

        states: [
            State {
                name: "entering"
                PropertyChanges { target: card; cardOpacity: 0; xOffset: -40 }
                PropertyChanges { target: scanLine; scanProgress: 0 }
            },
            State {
                name: "visible"
                PropertyChanges { target: card; cardOpacity: 1; xOffset: 0 }
                PropertyChanges { target: scanLine; scanProgress: 1 }
            },
            State {
                name: "closing"
                PropertyChanges { target: card; cardOpacity: 0; xOffset: 30 }
            }
        ]

        transitions: [
            Transition {
                from: "entering"; to: "visible"
                ParallelAnimation {
                    NumberAnimation {
                        target: card; property: "xOffset"
                        duration: 360; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: card; property: "cardOpacity"
                        duration: 240
                    }
                    NumberAnimation {
                        target: scanLine; property: "scanProgress"
                        from: 0; to: 1
                        duration: 550; easing.type: Easing.OutQuad
                    }
                }
            },
            Transition {
                from: "visible"; to: "closing"
                SequentialAnimation {
                    NumberAnimation {
                        target: card; property: "xShake"
                        from: 0; to: 6; duration: 50
                    }
                    NumberAnimation {
                        target: card; property: "xShake"
                        from: 6; to: -4; duration: 50
                    }
                    NumberAnimation {
                        target: card; property: "xShake"
                        from: -4; to: 0; duration: 50
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: card; property: "xOffset"
                            duration: 280; easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: card; property: "cardOpacity"
                            duration: 280
                        }
                    }
                    ScriptAction {
                        script: {
                            if (notif.notification) notif.notification.dismiss();
                        }
                    }
                }
            }
        ]

        Timer {
            id: closeTimer
            running: notif.state === "visible"
            repeat: false
            interval: {
                if (!notif.notification) return root.defaultTimeout;
                const t = notif.notification.expireTimeout;
                if (t < 0 || t === 0) {
                    return notif.urgency === 2 ? root.criticalTimeout : root.defaultTimeout;
                }
                return t;
            }
            onTriggered: notif.state = "closing"
        }

        // Transition entering → visible au montage
        Component.onCompleted: {
            Qt.callLater(() => { if (notif.state === "entering") notif.state = "visible"; });
        }

        Rectangle {
            id: card
            property real xOffset: 0
            property real xShake: 0
            property real cardOpacity: 0

            x: xOffset + xShake
            opacity: cardOpacity
            width: parent.width
            implicitHeight: contentCol.implicitHeight + 12

            color: "#d6cfb5"
            border.color: "#463f2e"
            border.width: 1

            // Bordure gauche colorée
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: notif.accentColor
            }

            // Scan-line d'entrée
            Rectangle {
                id: scanLine
                property real scanProgress: 0

                x: scanProgress * parent.width - 40
                y: 0
                width: 80
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#406e2a2a" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                opacity: scanProgress > 0 && scanProgress < 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
                clip: true
                z: 2
            }

            // Grille interne décorative
            Canvas {
                anchors.fill: parent
                anchors.leftMargin: 3
                opacity: 0.18
                z: 0
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.strokeStyle = "rgba(70, 63, 46, 0.25)";
                    ctx.lineWidth = 1;
                    for (let x = 0; x < width; x += 16) {
                        ctx.beginPath();
                        ctx.moveTo(x, 0); ctx.lineTo(x, height);
                        ctx.stroke();
                    }
                    for (let y = 0; y < height; y += 16) {
                        ctx.beginPath();
                        ctx.moveTo(0, y); ctx.lineTo(width, y);
                        ctx.stroke();
                    }
                }
            }

            ColumnLayout {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                anchors.topMargin: 10
                spacing: 6
                z: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: urgLabel.implicitWidth + 10
                        Layout.preferredHeight: 14
                        color: notif.accentColor

                        Text {
                            id: urgLabel
                            anchors.centerIn: parent
                            text: notif.urgencyLabel
                            color: "#d6cfb5"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 8
                            font.weight: Font.Medium
                            font.letterSpacing: 2
                        }
                    }

                    Text {
                        text: notif.urgencyJp
                        color: "#7a7358"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 9
                    }

                    Text {
                        Layout.fillWidth: true
                        text: notif.notification
                              ? (notif.notification.appName || "SYSTEM").toUpperCase()
                              : "SYSTEM"
                        color: "#7a7358"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.letterSpacing: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        text: {
                            const d = new Date();
                            const p = n => String(n).padStart(2, '0');
                            return `${p(d.getHours())}:${p(d.getMinutes())}`;
                        }
                        color: "#7a7358"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.letterSpacing: 1
                    }

                    Rectangle {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 14
                        color: closeMouse.containsMouse ? notif.accentColor : "transparent"
                        border.color: "#463f2e"
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: closeMouse.containsMouse ? "#d6cfb5" : "#463f2e"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 9
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notif.state = "closing"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#463f2e"
                    opacity: 0.2
                }

                // Zone contenu : image à gauche + texte à droite
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // ═══ THUMBNAIL (image ou icône) ═══
                    Item {
                        id: imageWrap
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        Layout.alignment: Qt.AlignTop

                        readonly property string imageSource: {
                            if (!notif.notification) return "";
                            // priorité à l'image embarquée, puis à l'appIcon
                            const img = notif.notification.image || "";
                            if (img.length > 0) return img;
                            const appIcon = notif.notification.appIcon || "";
                            if (appIcon.length > 0) {
                                // si c'est un chemin absolu
                                if (appIcon.startsWith("/") || appIcon.startsWith("file://")) {
                                    return appIcon;
                                }
                                // sinon c'est un nom d'icône de thème
                                return Quickshell.iconPath(appIcon, true);
                            }
                            return "";
                        }

                        visible: imageSource.length > 0

                        // Cadre style NieR
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: "#463f2e"
                            border.width: 1
                        }

                        // Badge ID coin supérieur gauche
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            width: 14
                            height: 10
                            color: notif.accentColor
                            z: 2

                            Text {
                                anchors.centerIn: parent
                                text: String(notif.itemIndex + 1).padStart(2, '0')
                                color: "#d6cfb5"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 7
                                font.letterSpacing: 0.5
                            }
                        }

                        // L'image
                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: imageWrap.imageSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 128
                            sourceSize.height: 128
                            smooth: true
                            visible: status === Image.Ready
                        }

                        // Petits repères décoratifs dans les coins
                        Repeater {
                            model: 4
                            delegate: Item {
                                required property int index
                                width: 4
                                height: 4
                                x: (index % 2 === 0) ? 0 : parent.width - 4
                                y: (index < 2) ? 0 : parent.height - 4
                                z: 3

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: (parent.parent.x === 0 || index % 2 === 0) ? parent.left : undefined
                                    anchors.right: (index % 2 === 1) ? parent.right : undefined
                                    width: 4
                                    height: 1
                                    color: notif.accentColor
                                    visible: index === 0 || index === 1
                                }
                            }
                        }
                    }

                    // ═══ TEXTE ═══
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: notif.notification ? notif.notification.summary : ""
                            color: "#2e2a1f"
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.letterSpacing: 0.8
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            visible: text.length > 0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: notif.notification ? notif.notification.body : ""
                            color: "#463f2e"
                            font.family: "Inter"
                            font.pixelSize: 11
                            font.weight: Font.Light
                            font.letterSpacing: 0.3
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            visible: text.length > 0
                            lineHeight: 1.4
                        }
                    }
                }

                // Actions (le Repeater accepte directement l'ObjectModel)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6
                    visible: actionRepeater.count > 0

                    Repeater {
                        id: actionRepeater
                        model: notif.notification ? notif.notification.actions : null

                        delegate: Rectangle {
                            required property var modelData

                            Layout.preferredHeight: 22
                            Layout.preferredWidth: actionText.implicitWidth + 16
                            color: actMouse.containsMouse ? "#463f2e" : "transparent"
                            border.color: "#463f2e"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: actionText
                                anchors.centerIn: parent
                                text: `▸ ${(modelData && modelData.text ? modelData.text : "").toUpperCase()}`
                                color: actMouse.containsMouse ? "#d6cfb5" : "#463f2e"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.letterSpacing: 1.5
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData && modelData.invoke) modelData.invoke();
                                    notif.state = "closing";
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }
            }

            // Barre de progression du timeout
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 3
                height: 1
                color: notif.accentColor
                opacity: 0.3
                z: 1

                Rectangle {
                    id: progressBar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width
                    color: notif.accentColor

                    NumberAnimation on width {
                        from: progressBar.parent.width
                        to: 0
                        duration: closeTimer.interval
                        running: notif.state === "visible"
                    }
                }
            }

            // Hover sur la carte → pause du timer
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.MiddleButton
                propagateComposedEvents: true
                z: 0

                onEntered: closeTimer.stop()
                onExited: {
                    if (notif.state === "visible") closeTimer.restart();
                }
                onClicked: (m) => {
                    if (m.button === Qt.MiddleButton) notif.state = "closing";
                }
            }
        }
    }
}