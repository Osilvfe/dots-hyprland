import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    readonly property int remaining: CodexUsage.primaryRemainingPercent
    readonly property bool warning: CodexUsage.primaryUsedPercent >= 80
    implicitWidth: quotaResource.implicitWidth + 8
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    onClicked: CodexUsage.refresh()

    Resource {
        id: quotaResource
        anchors.centerIn: parent
        iconName: "code"
        percentage: root.remaining / 100
        warning: root.warning
        warningThreshold: 101
        shown: true
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            StyledPopupHeaderRow {
                icon: "code"
                label: Translation.tr("Codex usage")
            }

            StyledPopupValueRow {
                icon: "schedule"
                label: `${CodexUsage.windowLabel(CodexUsage.primaryWindowMinutes)} ${Translation.tr("limit:")}`
                value: `${CodexUsage.primaryRemainingPercent}% ${Translation.tr("left")} · ${CodexUsage.primaryUsedPercent}% ${Translation.tr("used")}`
            }

            StyledPopupValueRow {
                visible: CodexUsage.primaryResetsAt > 0
                icon: "restart_alt"
                label: Translation.tr("Resets in:")
                value: CodexUsage.resetText(CodexUsage.primaryResetsAt)
            }

            StyledPopupValueRow {
                visible: CodexUsage.hasSecondary
                icon: "date_range"
                label: `${CodexUsage.windowLabel(CodexUsage.secondaryWindowMinutes)} ${Translation.tr("limit:")}`
                value: `${CodexUsage.secondaryRemainingPercent}% ${Translation.tr("left")} · ${CodexUsage.secondaryUsedPercent}% ${Translation.tr("used")}`
            }

            StyledPopupValueRow {
                visible: CodexUsage.hasSecondary && CodexUsage.secondaryResetsAt > 0
                icon: "restart_alt"
                label: Translation.tr("Resets in:")
                value: CodexUsage.resetText(CodexUsage.secondaryResetsAt)
            }

            StyledPopupValueRow {
                visible: CodexUsage.planType.length > 0
                icon: "workspace_premium"
                label: Translation.tr("Plan:")
                value: CodexUsage.planType
            }
        }
    }
}
