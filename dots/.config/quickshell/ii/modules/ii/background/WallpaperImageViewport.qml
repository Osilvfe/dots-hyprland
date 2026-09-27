pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property string sourcePath: ""
    property real imageX: 0
    property real imageY: 0
    property real imageWidth: width
    property real imageHeight: height
    property int imageFillMode: Image.PreserveAspectCrop
    property int textureWidth: Math.min(Math.max(1, Math.round(width)), 8192)
    property int textureHeight: Math.min(Math.max(1, Math.round(height)), 8192)

    property string lastReadySourcePath: ""
    property real naturalImageWidth: 0
    property real naturalImageHeight: 0

    readonly property bool sourceIsColor: /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(String(sourcePath || ""))
    readonly property bool ready: sourcePath === "" || sourceIsColor || (wallpaperImg.status === Image.Ready && lastReadySourcePath === sourcePath)
    readonly property int imageStatus: wallpaperImg.status

    signal loadFailed(string source)
    signal imageReady(real naturalWidth, real naturalHeight)

    clip: true

    function imageUrl(path) {
        if (!path || path === "") return "";
        return String(path).startsWith("/") ? ("file://" + path) : path;
    }

    Rectangle {
        anchors.fill: parent
        color: root.sourcePath
        visible: root.sourceIsColor
    }

    Image {
        id: wallpaperImg

        x: root.imageX
        y: root.imageY
        width: root.imageWidth
        height: root.imageHeight
        visible: root.sourcePath !== "" && !root.sourceIsColor
        source: visible ? root.imageUrl(root.sourcePath) : ""
        fillMode: root.imageFillMode
        asynchronous: true
        cache: true
        retainWhileLoading: true
        smooth: true
        sourceSize: Qt.size(root.textureWidth, root.textureHeight)

        onStatusChanged: {
            if (status === Image.Ready) {
                const srcW = Number(sourceSize.width);
                const srcH = Number(sourceSize.height);
                const impW = Number(implicitWidth);
                const impH = Number(implicitHeight);
                const w = (isFinite(srcW) && srcW > 0) ? srcW : (isFinite(impW) && impW > 0 ? impW : root.width);
                const h = (isFinite(srcH) && srcH > 0) ? srcH : (isFinite(impH) && impH > 0 ? impH : root.height);

                root.lastReadySourcePath = root.sourcePath;
                root.naturalImageWidth = w;
                root.naturalImageHeight = h;
                root.imageReady(w, h);
            } else if (status === Image.Error && root.sourcePath !== "") {
                root.loadFailed(root.sourcePath);
            }
        }
    }
}
