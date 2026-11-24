import QtQuick
import Quickshell
import Quickshell.Io

// The image quota record, read straight off the file the collector keeps in
// $XDG_STATE_HOME/omarchy/image-usage/usage.json. The panel never learns how
// the numbers were made; it only asks for a fresh run and reads what lands.
Item {
  id: root
  visible: false

  property var settings: ({})
  property var record: null
  property string parsedText: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string recordPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/image-usage/usage.json"
  readonly property string collector: decodeURIComponent(Qt.resolvedUrl("bin/omarchy-image-usage").toString().replace(/^file:\/\//, ""))
  readonly property bool running: updateProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // A minute is the floor. The quota moves only when an image is made, and
  // the server needn't be asked any more often than that.
  readonly property int refreshIntervalSec: Math.max(60, Number(setting("refreshIntervalSec", 300)) || 300)

  property bool pendingForce: false
  property bool pendingRun: false

  FileView {
    id: recordFile
    path: root.recordPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.clear()
  }

  function clear() {
    parsedText = ""
    record = null
  }

  function parse(content) {
    var text = String(content || "")
    if (record && text === parsedText) return
    try {
      var parsed = JSON.parse(text)
      record = parsed && typeof parsed === "object" ? parsed : null
      parsedText = record ? text : ""
    } catch (e) {
      console.warn("omarchy-image-usage", "Ignoring bad usage record", recordPath, e)
      clear()
    }
    scheduleRetry()
  }

  // A run that couldn't reach ChatGPT at all says so, and gets one sooner try
  // instead of waiting out the whole interval.
  function scheduleRetry() {
    if (record && record.retryAdvised === true) retryTimer.restart()
    else retryTimer.stop()
  }

  Timer {
    id: retryTimer
    interval: 30000
    repeat: false
    onTriggered: root.refresh(false)
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Process {
    id: updateProcess
    running: false
    onExited: {
      // The record is replaced with an atomic rename, which a watch can miss.
      recordFile.reload()
      if (root.pendingRun) {
        var force = root.pendingForce
        root.pendingRun = false
        root.pendingForce = false
        root.refresh(force)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("omarchy-image-usage", text.trim())
    }
  }

  // Forced runs skip the collector's one-minute reuse of its last answer.
  // Requests that arrive mid-run collapse into one more run afterwards.
  function refresh(force) {
    if (updateProcess.running) {
      pendingRun = true
      pendingForce = pendingForce || force === true
      return
    }
    updateProcess.command = force === true
      ? ["python3", "-I", collector, "--force"]
      : ["python3", "-I", collector]
    updateProcess.running = true
  }
}
