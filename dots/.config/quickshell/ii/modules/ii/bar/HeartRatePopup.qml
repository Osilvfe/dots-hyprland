import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root

    ColumnLayout {
        id: mainLayout
        implicitWidth: 230
        spacing: 8

        // Header: Icon, "Heart Rate", and Zone pill badge
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "ecg_heart"
                iconSize: Appearance.font.pixelSize.larger
                color: HeartRate.zoneColor
            }
            StyledText {
                Layout.fillWidth: true
                font.weight: Font.DemiBold
                text: Translation.tr("Heart Rate")
            }
            // Zone badge pill
            Rectangle {
                visible: HeartRate.bpm > 0
                implicitWidth: zoneText.implicitWidth + 12
                implicitHeight: 20
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(HeartRate.zoneColor, 0.8)
                border.width: 1
                border.color: ColorUtils.transparentize(HeartRate.zoneColor, 0.4)

                StyledText {
                    id: zoneText
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: HeartRate.zoneColor
                    text: Translation.tr(HeartRate.zoneName)
                }
            }
        }

        // Status rows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            StyledPopupValueRow {
                icon: "vital_signs"
                label: Translation.tr("Current:")
                value: HeartRate.bpm > 0 ? `${HeartRate.bpm} BPM` : Translation.tr("No Data")
            }
            StyledPopupValueRow {
                visible: HeartRate.deviceName.length > 0 || HeartRate.isMock || HeartRate.source === "udp"
                icon: HeartRate.isMock ? "smart_toy" : (HeartRate.source === "ble" ? "bluetooth" : "wifi")
                label: Translation.tr("Source:")
                value: {
                    if (HeartRate.isMock) return Translation.tr("Simulation (Mock)");
                    if (HeartRate.source === "udp") return Translation.tr("UDP (Port 9000)");
                    return HeartRate.deviceName || Translation.tr("Bluetooth LE");
                }
            }
            StyledPopupValueRow {
                visible: HeartRate.battery >= 0
                icon: "battery_android_full"
                label: Translation.tr("Sensor Battery:")
                value: `${HeartRate.battery}%`
            }
            StyledPopupValueRow {
                visible: HeartRate.totalSamples > 1
                icon: "timeline"
                label: Translation.tr("Min / Max:")
                value: `${HeartRate.minBpm} / ${HeartRate.maxBpm} BPM`
            }
            StyledPopupValueRow {
                visible: HeartRate.totalSamples > 1
                icon: "analytics"
                label: Translation.tr("Average:")
                value: `${HeartRate.avgBpm.toFixed(1)} BPM`
            }
        }

        // Sparkline trend chart
        ColumnLayout {
            Layout.fillWidth: true
            visible: HeartRate.history.length > 2
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Recent Trend")
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: `${HeartRate.history.length}s`
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true

                Canvas {
                    id: trendCanvas
                    anchors.fill: parent
                    anchors.margins: 4

                    readonly property var history: HeartRate.history
                    onHistoryChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (!history || history.length < 2) return;

                        let minVal = 999;
                        let maxVal = 0;
                        for (let i = 0; i < history.length; i++) {
                            const val = history[i];
                            if (val < minVal) minVal = val;
                            if (val > maxVal) maxVal = val;
                        }
                        if (maxVal === minVal) {
                            maxVal += 10;
                            minVal = Math.max(0, minVal - 10);
                        }
                        const range = (maxVal - minVal) * 1.15;
                        const baseMin = minVal - (range * 0.05);
                        const stepX = width / (history.length - 1);

                        // Gradient line
                        ctx.beginPath();
                        for (let i = 0; i < history.length; i++) {
                            const x = i * stepX;
                            const norm = Math.max(0, Math.min(1, (history[i] - baseMin) / range));
                            const y = height - (norm * height);
                            if (i === 0) {
                                ctx.moveTo(x, y);
                            } else {
                                ctx.lineTo(x, y);
                            }
                        }
                        ctx.strokeStyle = HeartRate.zoneColor;
                        ctx.lineWidth = 2;
                        ctx.stroke();

                        // Fill under curve
                        ctx.lineTo(width, height);
                        ctx.lineTo(0, height);
                        ctx.closePath();
                        ctx.fillStyle = ColorUtils.transparentize(HeartRate.zoneColor, 0.75);
                        ctx.fill();
                    }
                }
            }
        }

        // Action buttons row (Mock toggle & Reset stats)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 26
                buttonRadius: Appearance.rounding.small
                colBackground: HeartRate.isMock ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active

                onPressed: HeartRate.toggleMock()

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.smaller
                        text: HeartRate.isMock ? "check" : "smart_toy"
                        color: HeartRate.isMock ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: HeartRate.isMock ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                        text: HeartRate.isMock ? Translation.tr("Mock: On") : Translation.tr("Test Mock")
                    }
                }
            }

            RippleButton {
                visible: HeartRate.totalSamples > 0
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active

                onPressed: HeartRate.resetStats()

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.smaller
                    text: "refresh"
                    color: Appearance.colors.colOnLayer0
                }
            }
        }
    }
}
