import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property var profile: null
    readonly property bool hasProfile: profile !== null
    readonly property var curveData: (profile && profile.curve) ? profile.curve : []
    readonly property var filterNodes: (profile && profile.filterList) ? profile.filterList : []
    readonly property string profileKind: (profile && profile.kind) ? profile.kind : ""
    readonly property bool isParametric: profileKind === "parametric"
    readonly property bool isFir: profileKind === "fir"
    readonly property bool isEnabled: profile ? Boolean(profile.enabled) : false
    readonly property bool isActive: profile ? Boolean(profile.runtimeActive) : false

    property real hoverX: -1
    property real hoverY: -1
    property real probedFreq: 0
    property real probedGain: 0
    property var probedNode: null

    implicitWidth: 600
    implicitHeight: (isParametric && filterNodes.length > 0) ? 310 : 260

    function interpolateGain(targetFreq) {
        if (!root.curveData || root.curveData.length === 0)
            return 0;
        const pts = root.curveData;
        if (targetFreq <= pts[0].f)
            return pts[0].gain;
        if (targetFreq >= pts[pts.length - 1].f)
            return pts[pts.length - 1].gain;
        let low = 0;
        let high = pts.length - 1;
        while (high - low > 1) {
            const mid = Math.floor((low + high) / 2);
            if (pts[mid].f <= targetFreq)
                low = mid;
            else
                high = mid;
        }
        const p0 = pts[low];
        const p1 = pts[high];
        const logF0 = Math.log10(p0.f);
        const logF1 = Math.log10(p1.f);
        const t = (logF1 > logF0) ? (Math.log10(targetFreq) - logF0) / (logF1 - logF0) : 0;
        return p0.gain + t * (p1.gain - p0.gain);
    }

    function formatFreq(f) {
        if (f >= 1000) {
            const k = f / 1000;
            return (k >= 10 ? Math.round(k) : k.toFixed(1)) + " kHz";
        }
        return Math.round(f) + " Hz";
    }

    function formatGain(g) {
        return (g >= 0 ? "+" : "") + Number(g).toFixed(1) + " dB";
    }

    Rectangle {
        id: bgCard
        anchors.fill: parent
        color: Appearance.colors.colLayer2Base
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header row: Title, status pill, and probe readings
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Frequency response curve")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }

                Rectangle {
                    radius: 4
                    implicitHeight: 20
                    implicitWidth: statusText.implicitWidth + 12
                    color: !root.hasProfile
                        ? Appearance.colors.colLayer1Base
                        : root.isActive
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                            : root.isEnabled
                                ? ColorUtils.transparentize(Appearance.colors.colError, 0.8)
                                : Appearance.colors.colLayer1Base
                    border.width: 1
                    border.color: !root.hasProfile
                        ? Appearance.colors.colLayer0Border
                        : root.isActive
                            ? Appearance.colors.colPrimary
                            : root.isEnabled
                                ? Appearance.colors.colError
                                : Appearance.colors.colSubtext

                    StyledText {
                        id: statusText
                        anchors.centerIn: parent
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: !root.hasProfile
                            ? Appearance.colors.colSubtext
                            : root.isActive
                                ? Appearance.colors.colPrimary
                                : root.isEnabled
                                    ? Appearance.colors.colError
                                    : Appearance.colors.colSubtext
                        text: !root.hasProfile
                            ? Translation.tr("No profile imported for this device.")
                            : root.isActive
                                ? Translation.tr("Active")
                                : root.isEnabled
                                    ? Translation.tr("Enabled (Inactive)")
                                    : Translation.tr("Bypassed")
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    id: probeIndicator
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colPrimary
                    text: {
                        if (root.probedNode) {
                            return Translation.tr("Filter #%1 (%2): %3 · %4 dB · Q %5")
                                .arg(root.probedNode.id)
                                .arg(root.probedNode.kind)
                                .arg(root.formatFreq(root.probedNode.frequency))
                                .arg((root.probedNode.gain >= 0 ? "+" : "") + root.probedNode.gain)
                                .arg(root.probedNode.q);
                        }
                        if (root.hoverX >= 0 && root.hasProfile && root.curveData.length > 0) {
                            return root.formatFreq(root.probedFreq) + " · " + root.formatGain(root.probedGain);
                        }
                        if (root.hasProfile && root.curveData.length > 0) {
                            const minG = (root.profile && root.profile.minGain !== undefined) ? root.profile.minGain : 0;
                            const maxG = (root.profile && root.profile.maxGain !== undefined) ? root.profile.maxGain : 0;
                            return Translation.tr("Range: %1 ~ %2 dB").arg(root.formatGain(minG)).arg(root.formatGain(maxG));
                        }
                        return "";
                    }
                }
            }

            // Curve canvas area
            Item {
                id: plotContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: 180

                Canvas {
                    id: curveCanvas
                    anchors.fill: parent

                    readonly property real padLeft: 46
                    readonly property real padRight: 16
                    readonly property real padTop: 12
                    readonly property real padBottom: 22

                    readonly property real plotW: Math.max(10, width - padLeft - padRight)
                    readonly property real plotH: Math.max(10, height - padTop - padBottom)

                    readonly property real fMin: 20.0
                    readonly property real fMax: 20000.0
                    readonly property real logMin: Math.log10(fMin)
                    readonly property real logMax: Math.log10(fMax)

                    readonly property real rawMinG: (root.profile && root.profile.minGain !== undefined) ? root.profile.minGain : -12
                    readonly property real rawMaxG: (root.profile && root.profile.maxGain !== undefined) ? root.profile.maxGain : 12
                    readonly property real yMin: Math.floor(Math.min(-12, rawMinG - 1) / 6) * 6
                    readonly property real yMax: Math.ceil(Math.max(12, rawMaxG + 1) / 6) * 6

                    function freqToX(f) {
                        return padLeft + (Math.log10(Math.max(fMin, Math.min(fMax, f))) - logMin) / (logMax - logMin) * plotW;
                    }

                    function xToFreq(x) {
                        const clampedX = Math.max(padLeft, Math.min(padLeft + plotW, x));
                        return Math.pow(10, logMin + (clampedX - padLeft) / plotW * (logMax - logMin));
                    }

                    function gainToY(g) {
                        return padTop + (yMax - g) / (yMax - yMin) * plotH;
                    }

                    Connections {
                        target: root
                        function onCurveDataChanged() { curveCanvas.requestPaint(); }
                        function onProfileChanged() { curveCanvas.requestPaint(); }
                        function onIsActiveChanged() { curveCanvas.requestPaint(); }
                        function onIsEnabledChanged() { curveCanvas.requestPaint(); }
                    }

                    Connections {
                        target: Appearance
                        function onColorsChanged() { curveCanvas.requestPaint(); }
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        const mainCol = root.isActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext;
                        const mainColStr = mainCol.toString();
                        const subtextColStr = Appearance.colors.colSubtext.toString();
                        const gridColStr = ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.85).toString();
                        const subGridColStr = ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.93).toString();

                        // 1. Draw vertical frequency grid lines
                        const majorFreqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
                        const majorLabels = ["20", "50", "100", "200", "500", "1k", "2k", "5k", "10k", "20k"];
                        const minorFreqs = [
                            30, 40, 60, 70, 80, 90,
                            300, 400, 600, 700, 800, 900,
                            3000, 4000, 6000, 7000, 8000, 9000
                        ];

                        // Sub-grid lines
                        ctx.strokeStyle = subGridColStr;
                        ctx.lineWidth = 1;
                        ctx.setLineDash([]);
                        ctx.beginPath();
                        for (let i = 0; i < minorFreqs.length; i++) {
                            const x = freqToX(minorFreqs[i]);
                            ctx.moveTo(x, padTop);
                            ctx.lineTo(x, padTop + plotH);
                        }
                        ctx.stroke();

                        // Major grid lines & X-axis labels
                        ctx.font = "9px sans-serif";
                        ctx.fillStyle = subtextColStr;
                        ctx.textAlign = "center";
                        ctx.textBaseline = "top";

                        ctx.strokeStyle = gridColStr;
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        for (let i = 0; i < majorFreqs.length; i++) {
                            const x = freqToX(majorFreqs[i]);
                            ctx.moveTo(x, padTop);
                            ctx.lineTo(x, padTop + plotH);
                            ctx.fillText(majorLabels[i], x, padTop + plotH + 4);
                        }
                        ctx.stroke();

                        // 2. Draw horizontal dB gain grid lines & Y-axis labels
                        ctx.textAlign = "right";
                        ctx.textBaseline = "middle";

                        for (let g = yMin; g <= yMax; g += 6) {
                            const y = gainToY(g);
                            if (g === 0) {
                                // Highlight 0 dB reference line
                                ctx.strokeStyle = ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.5).toString();
                                ctx.lineWidth = 1.2;
                                ctx.setLineDash([4, 4]);
                            } else {
                                ctx.strokeStyle = gridColStr;
                                ctx.lineWidth = 1;
                                ctx.setLineDash([]);
                            }
                            ctx.beginPath();
                            ctx.moveTo(padLeft, y);
                            ctx.lineTo(padLeft + plotW, y);
                            ctx.stroke();

                            ctx.fillStyle = (g === 0) ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.3).toString() : subtextColStr;
                            ctx.fillText((g > 0 ? "+" : "") + g, padLeft - 6, y);
                        }
                        ctx.setLineDash([]);

                        // 3. Draw curve or empty baseline
                        const pts = root.curveData;
                        if (!pts || pts.length === 0) {
                            // Empty state: draw flat line at 0 dB
                            const zeroY = gainToY(0);
                            ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colSubtext, 0.6).toString();
                            ctx.lineWidth = 1.5;
                            ctx.setLineDash([6, 6]);
                            ctx.beginPath();
                            ctx.moveTo(padLeft, zeroY);
                            ctx.lineTo(padLeft + plotW, zeroY);
                            ctx.stroke();
                            ctx.setLineDash([]);
                            return;
                        }

                        // Gradient area fill under curve down to plot bottom
                        const fillGrad = ctx.createLinearGradient(0, padTop, 0, padTop + plotH);
                        if (root.isActive) {
                            fillGrad.addColorStop(0, ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72).toString());
                            fillGrad.addColorStop(1, ColorUtils.transparentize(Appearance.colors.colPrimary, 0.98).toString());
                        } else {
                            fillGrad.addColorStop(0, ColorUtils.transparentize(Appearance.colors.colSubtext, 0.86).toString());
                            fillGrad.addColorStop(1, ColorUtils.transparentize(Appearance.colors.colSubtext, 0.98).toString());
                        }

                        ctx.beginPath();
                        ctx.moveTo(freqToX(pts[0].f), padTop + plotH);
                        for (let i = 0; i < pts.length; i++) {
                            ctx.lineTo(freqToX(pts[i].f), gainToY(pts[i].gain));
                        }
                        ctx.lineTo(freqToX(pts[pts.length - 1].f), padTop + plotH);
                        ctx.closePath();
                        ctx.fillStyle = fillGrad;
                        ctx.fill();

                        // Response curve stroke
                        ctx.strokeStyle = mainColStr;
                        ctx.lineWidth = 2.2;
                        ctx.beginPath();
                        for (let i = 0; i < pts.length; i++) {
                            const x = freqToX(pts[i].f);
                            const y = gainToY(pts[i].gain);
                            if (i === 0)
                                ctx.moveTo(x, y);
                            else
                                ctx.lineTo(x, y);
                        }
                        ctx.stroke();

                        // 4. Draw Parametric EQ filter band nodes
                        if (root.isParametric && root.filterNodes && root.filterNodes.length > 0) {
                            for (let i = 0; i < root.filterNodes.length; i++) {
                                const node = root.filterNodes[i];
                                const nx = freqToX(node.frequency);
                                const ny = gainToY(root.interpolateGain(node.frequency));

                                // Outer ring
                                ctx.strokeStyle = mainColStr;
                                ctx.lineWidth = 2;
                                ctx.fillStyle = Appearance.colors.colLayer2Base.toString();
                                ctx.beginPath();
                                ctx.arc(nx, ny, 5, 0, 2 * Math.PI);
                                ctx.fill();
                                ctx.stroke();

                                // Inner core
                                ctx.fillStyle = mainColStr;
                                ctx.beginPath();
                                ctx.arc(nx, ny, 2.5, 0, 2 * Math.PI);
                                ctx.fill();
                            }
                        }

                        // 5. Draw mouse hover crosshair and probe dot
                        if (root.hoverX >= padLeft && root.hoverX <= padLeft + plotW) {
                            const hx = root.hoverX;
                            const hy = gainToY(root.probedGain);

                            // Vertical guideline
                            ctx.strokeStyle = ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.6).toString();
                            ctx.lineWidth = 1;
                            ctx.setLineDash([3, 3]);
                            ctx.beginPath();
                            ctx.moveTo(hx, padTop);
                            ctx.lineTo(hx, padTop + plotH);
                            ctx.stroke();
                            ctx.setLineDash([]);

                            // Outer glow
                            ctx.fillStyle = ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7).toString();
                            ctx.beginPath();
                            ctx.arc(hx, hy, 7, 0, 2 * Math.PI);
                            ctx.fill();

                            // Center dot
                            ctx.fillStyle = Appearance.colors.colPrimary.toString();
                            ctx.beginPath();
                            ctx.arc(hx, hy, 3.5, 0, 2 * Math.PI);
                            ctx.fill();
                        }
                    }
                }

                // Empty state overlay when no profile is imported
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !root.hasProfile || root.curveData.length === 0
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "graphic_eq"
                        font.pixelSize: 28
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No EQ profile imported")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Import an AutoEQ file to visualize the response curve.")
                        color: ColorUtils.transparentize(Appearance.colors.colSubtext, 0.4)
                        font.pixelSize: Appearance.font.pixelSize.smallie
                    }
                }

                // Interactive hover tracking
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true

                    onPositionChanged: mouse => {
                        const cl = curveCanvas.padLeft;
                        const cr = curveCanvas.padLeft + curveCanvas.plotW;
                        if (mouse.x >= cl && mouse.x <= cr) {
                            root.hoverX = mouse.x;
                            root.hoverY = mouse.y;
                            root.probedFreq = curveCanvas.xToFreq(mouse.x);
                            root.probedGain = root.interpolateGain(root.probedFreq);

                            // Detect nearby filter band node
                            let nearby = null;
                            if (root.isParametric && root.filterNodes) {
                                for (let i = 0; i < root.filterNodes.length; i++) {
                                    const node = root.filterNodes[i];
                                    const nx = curveCanvas.freqToX(node.frequency);
                                    if (Math.abs(mouse.x - nx) < 14) {
                                        nearby = node;
                                        break;
                                    }
                                }
                            }
                            root.probedNode = nearby;
                            curveCanvas.requestPaint();
                        } else {
                            if (root.hoverX >= 0) {
                                root.hoverX = -1;
                                root.hoverY = -1;
                                root.probedNode = null;
                                curveCanvas.requestPaint();
                            }
                        }
                    }

                    onExited: {
                        root.hoverX = -1;
                        root.hoverY = -1;
                        root.probedNode = null;
                        curveCanvas.requestPaint();
                    }
                }
            }

            // Bottom metadata badges and filter chips
            RowLayout {
                Layout.fillWidth: true
                visible: root.hasProfile
                spacing: 6

                // FIR details
                StyledText {
                    visible: root.isFir
                    Layout.fillWidth: true
                    text: Translation.tr("Minimum-phase FIR · %1 points").arg((root.profile && root.profile.points !== undefined) ? root.profile.points : 0)
                        + ((root.profile && root.profile.headroomAdjustment)
                            ? " · " + Translation.tr("Headroom: %1 dB").arg(Number(root.profile.headroomAdjustment).toFixed(1))
                            : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    elide: Text.ElideRight
                }

                // Parametric Preamp badge
                Rectangle {
                    visible: root.isParametric && root.profile && root.profile.preamp !== undefined
                    radius: 4
                    implicitHeight: 22
                    implicitWidth: preampText.implicitWidth + 12
                    color: Appearance.colors.colLayer1Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    StyledText {
                        id: preampText
                        anchors.centerIn: parent
                        text: Translation.tr("Preamp") + ": " + ((root.profile && root.profile.preamp >= 0) ? "+" : "") + Number((root.profile && root.profile.preamp !== undefined) ? root.profile.preamp : 0).toFixed(1) + " dB"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallie
                    }
                }

                // Parametric filter count badge
                StyledText {
                    visible: root.isParametric
                    text: Translation.tr("Parametric EQ · %1 bands").arg(root.filterNodes.length)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                }

                // Horizontal scrollable filter band chips for parametric EQ
                Item {
                    visible: root.isParametric && root.filterNodes.length > 0
                    Layout.fillWidth: true
                    implicitHeight: 24

                    StyledFlickable {
                        anchors.fill: parent
                        contentWidth: chipsRow.implicitWidth
                        contentHeight: parent.height
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true

                        RowLayout {
                            id: chipsRow
                            height: parent.height
                            spacing: 6

                            Repeater {
                                model: root.filterNodes.length

                                Rectangle {
                                    id: chip
                                    required property int index
                                    readonly property var modelData: root.filterNodes[index]
                                    radius: 12
                                    implicitHeight: 20
                                    implicitWidth: chipLabel.implicitWidth + 12
                                    color: (root.probedNode && modelData && root.probedNode.id === modelData.id)
                                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
                                        : Appearance.colors.colLayer1Base
                                    border.width: 1
                                    border.color: (root.probedNode && modelData && root.probedNode.id === modelData.id)
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colLayer0Border

                                    StyledText {
                                        id: chipLabel
                                        anchors.centerIn: parent
                                        text: "#" + (modelData ? modelData.id : "") + " " + (modelData ? modelData.kind : "") + " " + root.formatFreq(modelData ? modelData.frequency : 0) + " " + ((modelData && modelData.gain >= 0) ? "+" : "") + (modelData ? modelData.gain : 0) + "dB"
                                        font.pixelSize: 10
                                        color: (root.probedNode && modelData && root.probedNode.id === modelData.id)
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
