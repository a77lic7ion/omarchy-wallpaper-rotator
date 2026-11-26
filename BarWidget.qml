import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Owns all rotation state. The control script talks to the user systemd timer;
// the panel only reads these properties and calls the actions below.
BarWidget {
  id: root
  moduleName: "shaun.wallpaper-rotator"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace("file://", "")
  readonly property string ctlScript: pluginDir + "/scripts/rotatectl.sh"

  property bool loaded: false
  property bool busy: false
  property int interval: 5
  property bool active: true
  property string timerEnabled: ""
  property string theme: ""
  property int wallpapers: 0
  property int nextMin: 0
  property string error: ""
  property var themes: []
  property var selectedThemes: []
  property var folders: []

  readonly property string tooltipText: {
    if (!root.loaded) return "Wallpaper rotation — reading timer…"
    if (root.error !== "") return "Wallpaper rotation — " + root.error
    if (!root.active) return "Wallpaper rotation paused"
    return "Wallpaper — " + root.wallpapers + " images · next in ~" + root.nextMin
      + " min · every " + root.interval + " min"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }
  onBarChanged: injectPanel()

  // ---- control ------------------------------------------------------------

  function applyStatus(text) {
    var s
    try { s = JSON.parse(String(text || "{}")) } catch (e) { return }
    if (typeof s.interval === "number") root.interval = s.interval
    if (typeof s.active === "boolean") root.active = s.active
    if (typeof s.enabled === "string") root.timerEnabled = s.enabled
    if (typeof s.theme === "string") root.theme = s.theme
    if (typeof s.wallpapers === "number") root.wallpapers = s.wallpapers
    if (typeof s.nextMin === "number") root.nextMin = s.nextMin
    if (Array.isArray(s.themes)) root.selectedThemes = s.themes
    if (Array.isArray(s.folders)) root.folders = s.folders
    root.error = typeof s.error === "string" ? s.error : ""
    root.loaded = true
  }

  function applyThemes(text) {
    try {
      var list = JSON.parse(String(text || "[]"))
      if (Array.isArray(list)) root.themes = list
    } catch (e) { }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!themesProc.running) themesProc.running = true
  }

  function runAction(args) {
    if (root.busy) return
    root.busy = true
    actionProc.command = ["bash", root.ctlScript].concat(args)
    actionProc.running = true
  }

  // Panel-facing actions.
  function applyInterval(minutes) { root.runAction(["set", String(minutes)]) }
  function pause() { root.runAction(["pause"]) }
  function resume() { root.runAction(["resume"]) }
  function nextWallpaper() { root.runAction(["next"]) }
  function reset() { root.runAction(["reset"]) }
  function toggleTheme(id) { root.runAction(["theme", id, "toggle"]) }
  function allThemes(on) { root.runAction(["all-themes", on ? "on" : "off"]) }
  function addFolder(path) { root.runAction(["add-folder", path]) }
  function removeFolder(path) { root.runAction(["remove-folder", path]) }

  Component.onCompleted: root.refresh()

  Process {
    id: statusProc
    command: ["bash", root.ctlScript, "status"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: themesProc
    command: ["bash", root.ctlScript, "themes"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyThemes(text)
    }
  }

  Process {
    id: actionProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function (code) {
      root.busy = false
      if (code !== 0) root.error = "Command failed — check the script"
    }
  }

  // Keep the Active/Paused pill and "next in" hint current even when the
  // panel is closed.
  Timer {
    interval: 30000
    running: true
    repeat: true
    // Cheap status only — rescanning 70 themes every 30s is wasted work.
    onTriggered: { if (!statusProc.running) statusProc.running = true }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0c2"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.active
    tooltipText: root.tooltipText
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}
