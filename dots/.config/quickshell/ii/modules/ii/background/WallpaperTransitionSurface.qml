pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

Item {
    id: root

    property string sourcePath: ""
    property real imageX: 0
    property real imageY: 0
    property real imageWidth: width
    property real imageHeight: height
    property int imageFillMode: Image.PreserveAspectCrop
    property real shaderFillMode: 2 // 2 = Image.PreserveAspectCrop

    property string transitionType: Config.options.background.transition?.type ?? "random"
    property var includedTransitions: ["fade", "wipe", "disc", "stripes", "iris_bloom", "pixelate", "portal"]
    property int transitionDurationMs: Config.options.background.transition?.durationMs ?? 1000
    property string transitionEasingMode: Config.options.background.transition?.easingMode ?? "customBezier"
    property var transitionBezierCurve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property bool transitionsEnabled: Config.options.background.transition?.enable ?? true

    property int textureWidth: Math.min(Math.max(1, Math.round(width)), 8192)
    property int textureHeight: Math.min(Math.max(1, Math.round(height)), 8192)

    property int currentViewportIndex: 0
    readonly property WallpaperImageViewport currentViewport: currentViewportIndex === 0 ? viewportA : viewportB
    readonly property WallpaperImageViewport nextViewport: currentViewportIndex === 0 ? viewportB : viewportA
    readonly property string currentSource: currentViewport ? currentViewport.sourcePath : ""
    readonly property string nextSource: nextViewport ? nextViewport.sourcePath : ""

    property string activeTransition: "none"
    property real transitionProgress: 0
    property bool effectActive: false
    property string pendingSource: ""
    property bool nextIsImmediate: false

    property vector4d fillColor: Qt.vector4d(0, 0, 0, 1)
    property real edgeSmoothness: 0.1
    property real wipeDirection: 0
    property real discCenterX: 0.5
    property real discCenterY: 0.5
    property real stripesCount: 16
    property real stripesAngle: 30
    property int activeTransitionDurationMs: 1000
    property int activeTransitionEasingType: Easing.BezierSpline
    property var activeTransitionBezierCurve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property string lastError: ""

    readonly property bool ready: {
        if (root.sourcePath === "") return true;
        if (root.currentSource !== root.sourcePath) return false;
        return root.currentViewport.ready;
    }

    signal loadFailed(string source, string message)
    signal naturalImageDimensionsChanged(real width, real height)

    function shaderUrl(name) {
        return Qt.resolvedUrl("../../../assets/shaders/wallpaper/qsb/" + name + ".frag.qsb");
    }

    function isColorSource(path) {
        return /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(String(path || ""));
    }

    function chooseTransition() {
        let transition = root.transitionType;
        if (transition !== "random")
            return transition;

        const included = root.includedTransitions;
        if (!included || included.length === 0)
            return "fade";
        return included[Math.floor(Math.random() * included.length)];
    }

    function easingType(mode) {
        switch (mode) {
        case "linear":
            return Easing.Linear;
        case "quad":
            return Easing.InOutQuad;
        case "cubic":
            return Easing.InOutCubic;
        case "quart":
            return Easing.InOutQuart;
        case "sine":
            return Easing.InOutSine;
        case "customBezier":
        default:
            return Easing.BezierSpline;
        }
    }

    function setImmediate(path) {
        transitionAnimation.stop();
        const requested = path || "";
        if (requested !== "" && requested === root.nextSource && root.nextViewport.ready) {
            root.currentViewportIndex = root.currentViewportIndex === 0 ? 1 : 0;
            root.nextViewport.sourcePath = "";
        } else {
            root.currentViewport.sourcePath = requested;
            root.nextViewport.sourcePath = "";
        }
        root.pendingSource = "";
        root.activeTransition = "none";
        root.transitionProgress = 0;
        root.effectActive = false;
        root.nextIsImmediate = false;
    }

    function prepareTransition(type) {
        switch (type) {
        case "wipe":
            root.wipeDirection = Math.floor(Math.random() * 4);
            break;
        case "disc":
        case "pixelate":
        case "portal":
            root.discCenterX = 0.2 + Math.random() * 0.6;
            root.discCenterY = 0.2 + Math.random() * 0.6;
            break;
        case "stripes":
            root.stripesCount = Math.round(Math.random() * 16 + 6);
            root.stripesAngle = Math.random() * 360;
            break;
        case "iris bloom":
        case "iris_bloom":
            root.discCenterX = 0.5;
            root.discCenterY = 0.5;
            break;
        }
    }

    function startTransition() {
        if (!root.transitionsEnabled) {
            root.setImmediate(root.nextSource);
            return;
        }
        root.activeTransitionDurationMs = root.transitionDurationMs;
        root.activeTransitionEasingType = root.easingType(root.transitionEasingMode);
        root.activeTransitionBezierCurve = root.transitionEasingMode === "customBezier"
            ? root.transitionBezierCurve
            : [0, 0, 1, 1, 1, 1];
        console.log("[WallpaperTransition] Starting transition:", root.activeTransition, "to:", root.nextSource);
        root.effectActive = true;
        transitionDelayTimer.restart();
    }

    function acceptPreparedImage() {
        if (root.nextSource === "" || !root.nextViewport.ready)
            return;
        root.lastError = "";
        if (root.nextIsImmediate) {
            root.setImmediate(root.nextSource);
            return;
        }
        root.startTransition();
    }

    function requestWallpaper(path, immediate) {
        const requested = path || "";
        root.lastError = "";
        if (requested === "") {
            root.setImmediate("");
            return;
        }

        if (requested === root.currentSource && !root.nextSource)
            return;

        if (root.isColorSource(requested)) {
            root.setImmediate(requested);
            return;
        }

        if (root.currentSource === "") {
            root.setImmediate(requested);
            return;
        }

        if (transitionAnimation.running || root.effectActive) {
            root.pendingSource = requested;
            return;
        }

        root.nextIsImmediate = root.currentSource === ""
            || root.isColorSource(root.currentSource)
            || immediate
            || !root.transitionsEnabled
            || root.transitionType === "none"
            || root.transitionDurationMs <= 0;

        root.activeTransition = root.nextIsImmediate ? "none" : root.chooseTransition();
        if (root.activeTransition === "none") {
            root.nextIsImmediate = true;
        } else {
            root.prepareTransition(root.activeTransition);
        }

        root.transitionProgress = 0;
        root.nextViewport.sourcePath = requested;
        if (root.nextViewport.ready) {
            root.acceptPreparedImage();
        }
    }

    function handleViewportReady(viewport) {
        if (viewport === root.currentViewport) {
            root.naturalImageDimensionsChanged(viewport.naturalImageWidth, viewport.naturalImageHeight);
        }
        if (viewport !== root.nextViewport || root.nextSource === "" || transitionAnimation.running || root.effectActive)
            return;
        root.acceptPreparedImage();
    }

    function handleViewportFailure(viewport, source) {
        const message = "Failed to decode wallpaper: " + source;
        root.lastError = message;
        if (viewport === root.nextViewport) {
            root.nextViewport.sourcePath = "";
            root.nextIsImmediate = false;
        }
        root.loadFailed(source, message);
    }

    onSourcePathChanged: requestWallpaper(sourcePath, false)

    onTransitionsEnabledChanged: {
        if (!root.transitionsEnabled && root.effectActive) {
            const target = root.nextSource !== ""
                ? root.nextSource
                : (root.pendingSource !== "" ? root.pendingSource : root.currentSource);
            root.setImmediate(target);
        }
    }

    Component.onCompleted: requestWallpaper(sourcePath, true)

    WallpaperImageViewport {
        id: viewportA

        anchors.fill: parent
        sourcePath: ""
        imageX: root.imageX
        imageY: root.imageY
        imageWidth: root.imageWidth
        imageHeight: root.imageHeight
        imageFillMode: root.imageFillMode
        textureWidth: root.textureWidth
        textureHeight: root.textureHeight
        visible: root.currentViewport === viewportA || (root.nextViewport === viewportA && (root.effectActive || root.nextSource !== ""))
        opacity: (root.currentViewport === viewportA || root.effectActive) ? 1 : 0

        onReadyChanged: root.handleViewportReady(viewportA)
        onImageReady: (w, h) => {
            if (root.currentViewport === viewportA) {
                root.naturalImageDimensionsChanged(w, h);
            }
        }
        onLoadFailed: source => root.handleViewportFailure(viewportA, source)
    }

    WallpaperImageViewport {
        id: viewportB

        anchors.fill: parent
        sourcePath: ""
        imageX: root.imageX
        imageY: root.imageY
        imageWidth: root.imageWidth
        imageHeight: root.imageHeight
        imageFillMode: root.imageFillMode
        textureWidth: root.textureWidth
        textureHeight: root.textureHeight
        visible: root.currentViewport === viewportB || (root.nextViewport === viewportB && (root.effectActive || root.nextSource !== ""))
        opacity: (root.currentViewport === viewportB || root.effectActive) ? 1 : 0

        onReadyChanged: root.handleViewportReady(viewportB)
        onImageReady: (w, h) => {
            if (root.currentViewport === viewportB) {
                root.naturalImageDimensionsChanged(w, h);
            }
        }
        onLoadFailed: source => root.handleViewportFailure(viewportB, source)
    }

    ShaderEffectSource {
        id: srcCurrent

        sourceItem: root.effectActive ? root.currentViewport : null
        hideSource: root.effectActive
        live: root.effectActive
        mipmap: false
        recursive: false
        textureSize: Qt.size(root.textureWidth, root.textureHeight)
    }

    ShaderEffectSource {
        id: srcNext

        sourceItem: root.effectActive ? root.nextViewport : null
        hideSource: root.effectActive
        live: root.effectActive
        mipmap: false
        recursive: false
        textureSize: Qt.size(root.textureWidth, root.textureHeight)
    }

    Loader {
        id: effectLoader

        anchors.fill: parent
        active: root.effectActive
        visible: root.effectActive

        function transitionComponent(type) {
            switch (type) {
            case "wipe":
                return wipeComp;
            case "disc":
                return discComp;
            case "stripes":
                return stripesComp;
            case "iris bloom":
            case "iris_bloom":
                return irisComp;
            case "pixelate":
                return pixelateComp;
            case "portal":
                return portalComp;
            case "fade":
            default:
                return fadeComp;
            }
        }

        sourceComponent: transitionComponent(root.activeTransition)
    }

    Component {
        id: fadeComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_fade")
        }
    }

    Component {
        id: wipeComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real direction: root.wipeDirection
            property real smoothness: root.edgeSmoothness
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_wipe")
        }
    }

    Component {
        id: discComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real centerX: root.discCenterX
            property real centerY: root.discCenterY
            property real smoothness: root.edgeSmoothness
            property real aspectRatio: root.width / Math.max(1, root.height)
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_disc")
        }
    }

    Component {
        id: stripesComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real stripeCount: root.stripesCount
            property real angle: root.stripesAngle
            property real smoothness: root.edgeSmoothness
            property real aspectRatio: root.width / Math.max(1, root.height)
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_stripes")
        }
    }

    Component {
        id: irisComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real centerX: 0.5
            property real centerY: 0.5
            property real smoothness: root.edgeSmoothness
            property real aspectRatio: root.width / Math.max(1, root.height)
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_iris_bloom")
        }
    }

    Component {
        id: pixelateComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real centerX: root.discCenterX
            property real centerY: root.discCenterY
            property real smoothness: root.edgeSmoothness
            property real aspectRatio: root.width / Math.max(1, root.height)
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_pixelate")
        }
    }

    Component {
        id: portalComp

        ShaderEffect {
            anchors.fill: parent
            property variant source1: srcCurrent
            property variant source2: srcNext
            property real progress: root.transitionProgress
            property real centerX: root.discCenterX
            property real centerY: root.discCenterY
            property real smoothness: root.edgeSmoothness
            property real aspectRatio: root.width / Math.max(1, root.height)
            property real fillMode: root.shaderFillMode
            property real imageWidth1: root.width
            property real imageHeight1: root.height
            property real imageWidth2: root.width
            property real imageHeight2: root.height
            property real screenWidth: root.width
            property real screenHeight: root.height
            property vector4d fillColor: root.fillColor
            fragmentShader: root.shaderUrl("wp_portal")
        }
    }

    Timer {
        id: transitionDelayTimer

        interval: 16
        repeat: false
        onTriggered: transitionAnimation.restart()
    }

    NumberAnimation {
        id: transitionAnimation

        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: root.activeTransitionDurationMs
        easing.type: root.activeTransitionEasingType
        easing.bezierCurve: root.activeTransitionBezierCurve
        onFinished: {
            root.currentViewportIndex = root.currentViewportIndex === 0 ? 1 : 0;
            root.nextViewport.sourcePath = "";
            root.transitionProgress = 0;
            root.effectActive = false;

            if (root.pendingSource !== "") {
                const pending = root.pendingSource;
                root.pendingSource = "";
                Qt.callLater(() => root.requestWallpaper(pending, false));
            }
        }
    }
}
