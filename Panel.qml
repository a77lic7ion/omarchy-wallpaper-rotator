import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

// Panel half of the Wallpaper Rotation widget. The BarWidget owns all state;
// this panel renders it and forwards clicks back to the widget.
Panel {
  id: root
  moduleName: "shaun.wallpaper-rotator"
  manageIpc: false

  // KeyboardPanel requires a typed Item here — a `var` fails at the C++
  // boundary of mapToItem() when the panel opens.
  property Item anchorItem: null
  property var hostWidget: null

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color secondary: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.82)

  readonly property int interval: root.hostWidget ? root.hostWidget.interval : 5
  readonly property bool active: root.hostWidget ? root.hostWidget.active : true
  readonly property bool busy: root.hostWidget ? root.hostWidget.busy : false
  readonly property string theme: root.hostWidget ? root.hostWidget.theme : ""
  readonly property int wallpapers: root.hostWidget ? root.hostWidget.wallpapers : 0
  readonly property int nextMin: root.hostWidget ? root.hostWidget.nextMin : 0
  readonly property string error: root.hostWidget ? root.hostWidget.error : ""
  readonly property var themes: root.hostWidget ? root.hostWidget.themes : []
  readonly property var selectedThemes: root.hostWidget ? root.hostWidget.selectedThemes : []
  readonly property var folders: root.hostWidget ? root.hostWidget.folders : []

  readonly property var presets: [1, 2, 5, 10, 15, 30, 60]

  readonly property string subtitle: {
    var s = (root.theme || "unknown theme") + " · " + root.wallpapers + " wallpaper"
      + (root.wallpapers === 1 ? "" : "s")
    if (root.active && root.nextMin > 0) s += " · next in ~" + root.nextMin + " min"
    return s
  }

  function open() {
    controller.show()
    if (root.hostWidget) root.hostWidget.refresh()
    Qt.callLater(function () { catcher.forceActiveFocus() })
  }
  function close() { controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function applyCustom() {
    var n = parseInt(minutesField.text, 10)
    if (isNaN(n) || n < 1 || n > 240) return
    if (root.hostWidget) root.hostWidget.applyInterval(n)
  }

  function toggleTheme(id) { if (root.hostWidget) root.hostWidget.toggleTheme(id) }
  function allThemes(on) { if (root.hostWidget) root.hostWidget.allThemes(on) }
  function removeFolder(path) { if (root.hostWidget) root.hostWidget.removeFolder(path) }

  Process {
    id: folderPicker
    command: []
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "" && root.hostWidget) root.hostWidget.addFolder(path)
      }
    }
  }

  function pickFolder() {
    folderPicker.command = ["zenity", "--file-selection", "--directory",
      "--title=Choose a wallpaper folder"]
    folderPicker.running = true
  }

  KeyboardPanel {
    id: popout
    anchorItem: root.anchorItem
    // Centre above the bar instead of anchoring to the host item: this widget
    // can live inside Overflow's panel, where the host item's window is a
    // KeyboardPanel whose contentItem is a children alias — anchoring to it
    // throws on open and drops the card in the wrong place.
    centerOnBar: true
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: popout.fittedContentWidth(Style.space(430))
    contentHeight: popout.fittedContentHeight(body.implicitHeight, Style.space(960))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: body
        width: parent.width
        spacing: Style.spacing.panelGap

        // ------------------------------------------------------------ header
        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Column {
            width: parent.width - statusPill.width - parent.spacing
            spacing: Style.space(2)

            Text {
              text: "Wallpaper Rotation"
              color: Color.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.subtitle
              color: root.secondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: statusPill
            anchors.verticalCenter: parent.verticalCenter
            width: pillLabel.implicitWidth + Style.space(18)
            height: pillLabel.implicitHeight + Style.space(9)
            radius: height / 2
            color: Qt.rgba((root.active ? Color.accent : Color.urgent).r,
                           (root.active ? Color.accent : Color.urgent).g,
                           (root.active ? Color.accent : Color.urgent).b, 0.16)
            border.width: 1
            border.color: root.active ? Color.accent : Color.urgent

            Text {
              id: pillLabel
              anchors.centerIn: parent
              text: root.active ? "Active" : "Paused"
              color: root.active ? Color.accent : Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { foreground: Color.foreground }

        // ---------------------------------------------------------- interval
        Text {
          text: "INTERVAL"
          color: Color.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Repeater {
            model: root.presets
            Button {
              required property int modelData
              text: modelData + "m"
              selected: root.interval === modelData
              enabled: !root.busy
              foreground: Color.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              tooltipText: "Rotate every " + modelData + " minute" + (modelData === 1 ? "" : "s")
              onClicked: { if (root.hostWidget) root.hostWidget.applyInterval(modelData) }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          TextField {
            id: minutesField
            width: Style.space(80)
            text: String(root.interval)
            validator: IntValidator { bottom: 1; top: 240 }
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(6)
            onAccepted: root.applyCustom()
          }

          Text {
            id: unitText
            anchors.verticalCenter: parent.verticalCenter
            text: "minutes"
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Item {
            width: Math.max(0, parent.width - minutesField.width - unitText.width
                            - applyButton.width - parent.spacing * 3)
            height: 1
          }

          Button {
            id: applyButton
            text: "Apply"
            enabled: !root.busy
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Apply the custom interval"
            onClicked: root.applyCustom()
          }
        }

        PanelSeparator { foreground: Color.foreground }

        // ---------------------------------------------------------- controls
        Text {
          text: "CONTROLS"
          color: Color.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.active ? "#5a8f6e" : Color.urgent
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.error !== "" ? root.error
              : (root.active ? "Timer running · every " + root.interval + " min"
                             : "Rotation paused")
            color: root.error !== "" ? Color.urgent : root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Button {
            id: nextButton
            text: "Next wallpaper"
            iconText: "\uf021"
            enabled: !root.busy
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Rotate once now"
            onClicked: { if (root.hostWidget) root.hostWidget.nextWallpaper() }
          }

          Button {
            id: pauseButton
            text: root.active ? "Pause rotation" : "Resume rotation"
            iconText: root.active ? "\uf28d" : "\uf04d"
            enabled: !root.busy
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: root.active ? "Disable the rotation timer" : "Enable the rotation timer"
            onClicked: {
              if (!root.hostWidget) return
              if (root.active) root.hostWidget.pause()
              else root.hostWidget.resume()
            }
          }

          Item {
            width: Math.max(0, parent.width - nextButton.width - pauseButton.width
                            - parent.spacing * 2)
            height: 1
          }
        }

        PanelSeparator { foreground: Color.foreground }

        // ------------------------------------------------------------ themes
        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "THEMES"
            color: Color.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item {
            width: Math.max(0, parent.width - themeLabel.width - allButton.width
              - noneButton.width - parent.spacing * 4)
            height: 1
          }

          Text {
            id: themeLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.selectedThemes.length === 0 ? "active theme only"
              : root.selectedThemes.length + " on"
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: noneButton
            text: "None"
            enabled: !root.busy
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            tooltipText: "Rotate only the active theme"
            onClicked: root.allThemes(false)
          }

          Button {
            id: allButton
            text: "All"
            enabled: !root.busy
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            tooltipText: "Select every installed theme"
            onClicked: root.allThemes(true)
          }
        }

        Flickable {
          id: themeScroller
          width: parent.width
          height: Math.min(168, themeList.implicitHeight)
          contentWidth: width
          contentHeight: themeList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: themeList
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.themes

              delegate: Rectangle {
                id: themeRow
                required property var modelData

                readonly property bool selected: root.selectedThemes.indexOf(modelData.id) !== -1

                width: parent.width
                height: 26
                radius: 4
                color: themeHover.hovered
                  ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.09)
                  : "transparent"

                Rectangle {
                  x: 3
                  anchors.verticalCenter: parent.verticalCenter
                  width: 16
                  height: 16
                  radius: 3
                  border.width: 1
                  border.color: themeRow.selected ? Color.accent : Color.foreground
                  color: themeRow.selected ? Color.accent : "transparent"

                  Text {
                    anchors.centerIn: parent
                    visible: themeRow.selected
                    text: "\u2713"
                    color: Color.background
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                  }
                }

                Text {
                  x: 27
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 100
                  text: modelData.name
                  color: Color.foreground
                  opacity: modelData.count > 0 ? 1 : 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.count > 0 ? modelData.count + " images" : "no art"
                  color: root.secondary
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                HoverHandler {
                  id: themeHover
                  cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleTheme(modelData.id)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: Color.foreground }

        // ----------------------------------------------------------- folders
        Text {
          text: "LOCAL FOLDERS"
          color: Color.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.folders

            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.spacing.sm

              Text {
                width: parent.width - removeButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }

              Button {
                id: removeButton
                text: "\u2715"
                enabled: !root.busy
                foreground: Color.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                tooltipText: "Stop rotating this folder"
                onClicked: root.removeFolder(modelData)
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Button {
            text: "Add folder"
            iconText: "\uf07b"
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Choose a folder of wallpapers"
            onClicked: root.pickFolder()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Top-level images and videos"
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ------------------------------------------------------------ footer
        Row {
          width: parent.width
          spacing: Style.spacing.rowGap

          Text {
            id: escText
            text: "Esc to close"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            width: Math.max(0, parent.width - escText.width - resetText.width
                            - parent.spacing * 2)
            height: 1
          }

          Text {
            id: resetText
            text: "Reset to 5 min default"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { if (root.hostWidget) root.hostWidget.reset() }
            }
          }
        }
        }
      }
    }
  }
}
