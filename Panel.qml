import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One bar icon and one panel for the ChatGPT subscription's image generation
// limit, the one Codex's built-in image_gen tool runs into: how much of it is
// used, and when it resets. Built after omarchy.agents, whose look and
// controls it follows.
Panel {
  id: root
  moduleName: "io.github.yousefelghoul.image-usage"
  ipcTarget: "io.github.yousefelghoul.image-usage"
  manageIpc: false

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Commons.Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "󰋩"

  readonly property var record: usage.record
  readonly property real warnAt: clamp(Number(setting("warnPercent", 90)), 0, 100) / 100

  property double nowMs: Date.now()

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, isFinite(v) ? v : lo)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function tr(key, fallback) { return Commons.I18n.t("imageUsage." + key, fallback) }
  function num(value) { return Commons.I18n.formatNumber(value) }

  // ---------------------------------------------------------------- reading

  // A window whose reset has passed is empty again, whatever the last
  // reading said, until the next one lands.
  readonly property var windows: {
    var list = record && Array.isArray(record.limits) ? record.limits : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var reset = new Date(String(entry.resetsAt || "")).getTime()
      var expired = isFinite(reset) && reset <= nowMs
      out.push({
        title: String(entry.title || "Limit"),
        percent: expired ? 0 : clamp(Number(entry.percent), 0, 1),
        resetAt: expired ? "" : String(entry.resetsAt || "")
      })
    }
    return out
  }

  // The fullest window is the one that stops the next image.
  readonly property var binding: {
    var best = null
    for (var i = 0; i < windows.length; i++)
      if (!best || windows[i].percent > best.percent) best = windows[i]
    return best
  }
  readonly property bool reached: !!binding && binding.percent >= 1
  readonly property bool alarming: !!binding && binding.percent >= warnAt

  readonly property bool needsSignIn: {
    var status = String(record && record.usageStatusText || "")
    return status === "Sign-in expired" || status === "Waiting for auth"
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return tr("durationNow", "now")
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return tr("durationDaysHours", "%1d %2h").arg(num(days)).arg(num(hours % 24))
    if (hours > 0) return tr("durationHoursMinutes", "%1h %2m").arg(num(hours)).arg(num(minutes % 60))
    return tr("durationMinutes", "%1m").arg(num(Math.max(1, minutes)))
  }

  function resetClock(w) {
    if (resetMsFor(w) <= 0) return ""
    var at = new Date(w.resetAt)
    var locale = Qt.locale(Commons.I18n.formatLocale)
    var sameDay = at.toDateString() === new Date(nowMs).toDateString()
    return sameDay ? at.toLocaleTimeString(locale, Locale.ShortFormat)
      : at.toLocaleString(locale, "ddd " + locale.timeFormat(Locale.ShortFormat))
  }

  function windowTitle(title) {
    switch (String(title || "")) {
    case "Daily": return tr("windowDaily", "Daily")
    case "Weekly": return tr("windowWeekly", "Weekly")
    case "Monthly": return tr("windowMonthly", "Monthly")
    case "Limit": return tr("windowLimit", "Limit")
    }
    return String(title || "")
  }

  function usedText(w) {
    return tr("percentUsed", "%1% used").arg(num(Math.round(w.percent * 100)))
  }

  // The collector's status lines are fixed English; the ones that reach the
  // screen go through the translation catalogue with their English fallback.
  function statusText() {
    var value = String(record && record.usageStatusText || "")
    switch (value) {
    case "Sign-in expired": return tr("signInExpired", "Sign-in expired")
    case "Waiting for auth": return tr("waitingForAuth", "Waiting for auth")
    case "No ChatGPT login": return tr("noChatgptLogin", "No ChatGPT login")
    case "Image limit unavailable": return tr("unavailable", "Image limit unavailable")
    }
    return value
  }

  function helpText() {
    var value = String(record && record.authHelpText || "")
    if (value === "Run `codex login` to authenticate.") return tr("helpCodexLogin", "Run %1 to authenticate.").arg("`codex login`")
    if (value === "codex not found in PATH") return tr("helpNoCodex", "%1 not found in PATH").arg("codex")
    return value
  }

  // What keeps the numbers from being current, said beside the last ones
  // known, which stay on show until a check succeeds again.
  function staleNote() {
    if (!record || needsSignIn || record.limitsStale !== true) return ""
    return helpText() || statusText()
  }

  function updatedText() {
    var at = record ? Number(record.limitsFetchedAt || 0) : 0
    if (!(at > 0)) return usage.running ? tr("checking", "Checking…") : ""
    var age = nowMs - at
    return age < 60000 ? tr("updatedJustNow", "Updated just now") : tr("updatedAgo", "Updated %1 ago").arg(formatDuration(age))
  }

  // The hero's line under the title: the answer at a glance.
  readonly property string summary: {
    if (!record) return usage.running ? tr("checking", "Checking…") : tr("noData", "No reading yet")
    if (needsSignIn || (!binding && statusText() !== "")) return statusText()
    if (!binding) return tr("noData", "No reading yet")
    // The countdown is on the window's own row; the hero only says where
    // things stand.
    if (reached) return tr("reached", "Limit reached")
    return usedText(binding)
  }

  readonly property string barTooltip: {
    var lines = [tr("title", "Image generation")]
    if (summary !== "") lines.push(summary)
    if (binding && !reached && resetMsFor(binding) > 0) lines.push(tr("resetsIn", "Resets in %1").arg(formatDuration(resetMsFor(binding))))
    return lines.join("\n")
  }

  // ---------------------------------------------------------------- actions

  function refreshNow() {
    nowMs = Date.now()
    usage.refresh(true)
  }

  // Codex holds the login the limit is read with; signing in again is
  // signing Codex in again, in the home the record was read from.
  function signIn() {
    var home = String(record && record.home || "")
    var command = (home !== "" ? "CODEX_HOME=" + Util.shellQuote(home) + " " : "") + "codex login"
    if (bar) bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(command))
    close()
  }

  // The keyboard walks the panel's actions in reading order.
  readonly property var actions: needsSignIn ? ["refresh", "signin"] : ["refresh"]
  property int keyIndex: -1
  function hasKey(name) { return keyIndex >= 0 && actions[keyIndex] === name }
  function moveKey(step) {
    keyIndex = keyIndex < 0 ? 0 : (keyIndex + step + actions.length) % actions.length
  }
  function activate() {
    var action = keyIndex >= 0 ? actions[keyIndex] : (needsSignIn ? "signin" : "refresh")
    if (action === "signin") signIn()
    else refreshNow()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    keyIndex = -1
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    // The collector reuses an answer under a minute old, so opening and
    // closing the panel in a row asks ChatGPT once.
    usage.refresh(false)
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Usage {
    id: usage
    settings: root.settings
  }

  // Countdowns and ages read nowMs, so the panel keeps telling the truth
  // while it sits open, and the tooltip while it doesn't.
  Timer {
    interval: root.opened ? 30000 : 60000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.alarming
    dimmed: !root.record || root.needsSignIn
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton || buttonCode === Qt.RightButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      property alias panelFlick: panelFlick
      implicitHeight: column.implicitHeight
      anchors.fill: parent

      onMoveRequested: function(dx, dy) { root.moveKey(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(16)

          // ---------- Hero: image generation · summary · refresh ----------
          PanelHero {
            width: parent.width
            title: root.tr("title", "Image generation")
            meta: root.summary
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.glyph
                color: root.alarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              HeroButton {
                hasCursor: root.hasKey("refresh")
                glyph: "󰑐"
                spinning: usage.running
                tooltip: root.tr("refresh", "Refresh now")
                onHovered: root.keyIndex = root.actions.indexOf("refresh")
                onClicked: root.refreshNow()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Codex · plan ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(mark.height, accountName.implicitHeight)

            Mark {
              id: mark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: accountName
              anchors.left: mark.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Codex"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true

              HoverHandler { id: nameHover }

              PanelToolTip {
                visible: nameHover.hovered
                text: root.tr("viaCodex", "The limit Codex's image_gen tool runs into, read with its ChatGPT sign-in")
              }
            }

            Text {
              id: note
              anchors.left: accountName.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: accountName.verticalCenter
              readonly property string message: root.staleNote()
              visible: message !== ""
              text: "󰋽"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption

              HoverHandler { id: noteHover }

              PanelToolTip {
                visible: noteHover.hovered && note.visible
                implicitWidth: Math.min(implicitContentWidth + leftPadding + rightPadding, Style.space(320))
                text: note.message
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(root.record && root.record.plan || "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          TextLink {
            visible: root.needsSignIn
            picked: root.hasKey("signin")
            text: root.tr("signInRequired", "Sign-in required")
            idleColor: root.urgent
            tooltip: root.helpText()
            onClicked: root.signIn()
          }

          Text {
            visible: !root.needsSignIn && root.windows.length === 0 && text !== ""
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.helpText() || root.statusText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ---------- One row per window: title · meter · reset ----------
          Column {
            visible: root.windows.length > 0
            width: parent.width
            spacing: Style.space(12)

            Repeater {
              model: root.windows

              CompactLimit {
                required property var modelData
                width: column.width
                window: modelData
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.updatedText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- parts

  // The Codex mark, white on dark surfaces and black on light ones, the way
  // the agents panel picks between its marks.
  function luminance(color) {
    function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
  }

  component Mark: Item {
    id: markItem
    property real size: Style.font.heading
    width: size
    height: size

    Image {
      id: markImage
      anchors.fill: parent
      source: Qt.resolvedUrl(root.luminance(root.surface) >= 0.5 ? "assets/codex-light.svg" : "assets/codex.svg")
      sourceSize.width: markItem.size * 2
      sourceSize.height: markItem.size * 2
      fillMode: Image.PreserveAspectFit
    }

    Text {
      anchors.centerIn: parent
      visible: markImage.status !== Image.Ready
      textFormat: Text.PlainText
      text: root.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: markItem.size
    }
  }

  // One line per limit window: title, meter, and time to the reset, with the
  // exact share used and the reset time in its tooltip. As the agents panel
  // draws it.
  component CompactLimit: Item {
    id: compact
    property var window: null
    readonly property real resetMs: root.resetMsFor(window)
    implicitHeight: compactRow.height + (compactClock.visible ? compactClock.anchors.topMargin + compactClock.implicitHeight : 0)

    // The row's own line, so the reset time can sit underneath it.
    Item {
      id: compactRow
      width: parent.width
      height: Math.max(compactTitle.implicitHeight, compactValue.implicitHeight)
    }

    HoverHandler { id: compactHover }

    PanelToolTip {
      visible: compactHover.hovered && !!compact.window
      text: {
        if (!compact.window) return ""
        var lines = [root.usedText(compact.window)]
        if (compact.resetMs > 0) lines.push(root.tr("resetsAt", "Resets %1").arg(root.resetClock(compact.window)))
        return lines.join("\n")
      }
    }

    Text {
      id: compactTitle
      textFormat: Text.PlainText
      width: parent.width * 0.3
      anchors.verticalCenter: compactRow.verticalCenter
      text: compact.window ? root.windowTitle(compact.window.title) : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Meter {
      id: compactMeter
      anchors.left: compactTitle.right
      anchors.right: compactValue.left
      anchors.rightMargin: Style.space(20)
      anchors.verticalCenter: compactRow.verticalCenter
      value: compact.window ? compact.window.percent : -1
      alarming: compact.window && compact.window.percent >= root.warnAt
    }

    TextMetrics {
      id: compactValueMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: "00h 00m"
    }

    Text {
      id: compactValue
      width: Math.ceil(compactValueMetrics.advanceWidth)
      anchors.right: parent.right
      anchors.verticalCenter: compactRow.verticalCenter
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignRight
      text: compact.resetMs > 0 ? root.formatDuration(compact.resetMs) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // The exact time the window resets, small, under the start of the meter.
    Text {
      id: compactClock
      visible: text !== ""
      anchors.left: compactMeter.left
      anchors.top: compactRow.bottom
      anchors.topMargin: Style.space(4)
      textFormat: Text.PlainText
      text: compact.resetMs > 0 ? Qt.formatTime(new Date(compact.window.resetAt), "HH:mm") : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component HeroButton: Rectangle {
    id: heroButton
    signal clicked()
    signal hovered()
    property string glyph: ""
    property string tooltip: ""
    property bool hasCursor: false
    property bool spinning: false
    implicitWidth: Style.space(34)
    implicitHeight: implicitWidth
    radius: Style.cornerRadius
    color: root.alpha(Commons.Color.accent, hasCursor ? 0.3 : 0.12)
    border.width: hasCursor ? Math.max(1, Style.hoverBorderWidth) : 0
    border.color: Commons.Color.accent

    Text {
      id: heroGlyph
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: heroButton.glyph
      color: Commons.Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading

      RotationAnimation on rotation {
        running: heroButton.spinning
        from: 0; to: 360
        duration: 900
        loops: Animation.Infinite
        onRunningChanged: if (!running) heroGlyph.rotation = 0
      }
    }

    MouseArea {
      id: heroMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: heroButton.hovered()
      onClicked: heroButton.clicked()
    }

    PanelToolTip {
      visible: heroMouse.containsMouse
      text: heroButton.tooltip
    }
  }

  component TextLink: Text {
    id: link
    signal clicked()
    property bool picked: false
    property string tooltip: ""
    property color idleColor: root.dim
    readonly property bool hot: linkMouse.containsMouse || picked
    textFormat: Text.PlainText
    color: hot ? root.foreground : idleColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: hot

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }

    PanelToolTip {
      visible: link.tooltip !== "" && linkMouse.containsMouse
      text: link.tooltip
    }
  }

  // Rounded track showing the share of the limit used, as the agents panel
  // draws it.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
      }
    }
  }
}
