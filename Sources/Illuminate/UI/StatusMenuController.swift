import AppKit
import IlluminateCore

/// The menu-bar item and its menu. All state lives in `BoostController`;
/// this class only renders it and forwards user input.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let controller: BoostController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var isMenuOpen = false

    private let headerView = HeaderView()
    private let sliderView: SliderView
    private let toggleItem = NSMenuItem(title: "Boost Brightness", action: #selector(toggleBoost), keyEquivalent: "i")
    private let displaysSeparator = NSMenuItem.separator()
    private var displayItems: [NSMenuItem] = []
    private let overlayItem = NSMenuItem(title: "Overlay (Recommended)", action: #selector(selectOverlay), keyEquivalent: "")
    private let gammaItem = NSMenuItem(title: "Gamma Table", action: #selector(selectGamma), keyEquivalent: "")
    private var batteryItems: [NSMenuItem] = []
    private let lowPowerItem = NSMenuItem(title: "In Low Power Mode", action: #selector(toggleLowPower), keyEquivalent: "")
    private let playbackItem = NSMenuItem(title: "While Video Plays", action: #selector(togglePlayback), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    init(controller: BoostController) {
        self.controller = controller
        sliderView = SliderView()
        super.init()
        sliderView.onChange = { [weak self] level in
            self?.controller.update {
                $0.isEnabled = true
                $0.level = level
            }
        }
        buildMenu()
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("Illuminate")
        refresh()
    }

    /// Re-renders from the controller's state; called on any change. The menu's
    /// contents are only rendered while it is open, because `menuWillOpen` catches up.
    func refresh() {
        let preferences = controller.preferences
        let boosting = controller.isBoosting

        let symbol = boosting ? "sun.max.fill" : preferences.isEnabled && controller.hasEligibleDisplay ? "sun.max" : "sun.min"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: boosting ? "Boost on" : "Boost off")
        image?.isTemplate = true
        statusItem.button?.image = image

        guard isMenuOpen else { return }
        headerView.subtitle = summary
        toggleItem.state = preferences.isEnabled ? .on : .off
        toggleItem.isEnabled = controller.hasEligibleDisplay
        sliderView.level = preferences.level
        sliderView.isEnabled = controller.hasEligibleDisplay

        refreshDisplayItems()

        overlayItem.state = controller.effectiveTechnique == .overlay ? .on : .off
        gammaItem.state = controller.effectiveTechnique == .gamma ? .on : .off
        gammaItem.isEnabled = !controller.gammaCompatibility.isGammaBroken
        for item in batteryItems {
            let threshold = item.representedObject as? Int
            item.state = threshold == preferences.batteryThreshold ? .on : .off
        }
        lowPowerItem.state = preferences.pauseInLowPowerMode ? .on : .off
        playbackItem.state = preferences.reduceDuringPlayback ? .on : .off
    }

    // MARK: Menu construction

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem()
        header.view = headerView
        menu.addItem(header)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(toggleItem)
        let slider = NSMenuItem()
        slider.view = sliderView
        menu.addItem(slider)

        menu.addItem(displaysSeparator)

        let method = NSMenuItem(title: "Method", action: nil, keyEquivalent: "")
        let methodMenu = NSMenu()
        methodMenu.autoenablesItems = false
        for item in [overlayItem, gammaItem] {
            item.target = self
            methodMenu.addItem(item)
        }
        overlayItem.toolTip = "Multiplies the screen in EDR space. Keeps HDR video intact and leaves nothing behind if the app quits."
        gammaItem.toolTip = controller.gammaCompatibility.isGammaBroken
            ? "Not available: macOS ignores gamma tables on M5 Pro and M5 Max."
            : "Scales the display's gamma table. Colour-faithful, but clips HDR video and conflicts with f.lux."
        method.submenu = methodMenu
        menu.addItem(method)

        let pause = NSMenuItem(title: "Pause Boost", action: nil, keyEquivalent: "")
        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        pauseMenu.addItem(.sectionHeader(title: "On Battery"))
        for threshold in [nil, 10, 20, 30, 50] as [Int?] {
            let title = threshold.map { "Below \($0) %" } ?? "Never"
            let item = NSMenuItem(title: title, action: #selector(selectBatteryThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = threshold
            batteryItems.append(item)
            pauseMenu.addItem(item)
        }
        pauseMenu.addItem(.separator())
        for item in [lowPowerItem, playbackItem] {
            item.target = self
            pauseMenu.addItem(item)
        }
        playbackItem.toolTip = "Drops the boost while a player keeps the display awake, so HDR highlights are not blown out."
        pause.submenu = pauseMenu
        menu.addItem(pause)

        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Illuminate", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Illuminate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// Only on menu open and after a toggle: the state can change in System Settings,
    /// but reading it costs a round-trip to the system.
    private func refreshLoginItem() {
        let state = LoginItem.state
        loginItem.state = switch state {
        case .enabled: .on
        case .requiresApproval: .mixed
        case .disabled: .off
        }
        let location = LoginItem.location
        // Turning it off must always work; turning it on needs a stable install path.
        loginItem.isEnabled = location.canRegisterLoginItem || state == .enabled
        loginItem.toolTip = switch location {
        case .diskImage, .translocated:
            "Move Illuminate to the Applications folder and open it from there to start it at login."
        case _ where state == .requiresApproval:
            "Allow Illuminate under System Settings › General › Login Items."
        default:
            "Start Illuminate automatically when you log in."
        }
    }

    private func refreshDisplayItems() {
        displayItems.forEach(menu.removeItem)
        displayItems = controller.statuses.map { status in
            let item = NSMenuItem(title: status.name, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if #available(macOS 14.4, *) {
                item.subtitle = Self.describe(status)
            } else {
                item.title = "\(status.name): \(Self.describe(status))"
            }
            return item
        }
        var index = menu.index(of: displaysSeparator) + 1
        for item in displayItems {
            menu.insertItem(item, at: index)
            index += 1
        }
        if !displayItems.isEmpty {
            let separator = NSMenuItem.separator()
            menu.insertItem(separator, at: index)
            displayItems.append(separator)
        }
    }

    private var summary: String {
        let preferences = controller.preferences
        guard controller.hasEligibleDisplay else { return "No XDR display connected" }
        guard preferences.isEnabled else { return "Off" }
        if let reason = controller.suspension.primaryReason { return "Paused: \(Self.describe(reason))" }
        if controller.isPlaybackLikely && preferences.reduceDuringPlayback { return "Reduced while video plays" }
        let statuses = controller.statuses
        if statuses.contains(where: { $0.state == .boosting }) {
            let gain = statuses.map(\.gain).max() ?? 1
            return String(format: "Boosting %.2f×", gain)
        }
        return statuses.contains { $0.state == .unavailable } ? "Display refused EDR" : "Waiting for EDR…"
    }

    private static func describe(_ status: DisplayStatus) -> String {
        switch status.state {
        case .off: "Off"
        case .engaging: "Requesting EDR headroom…"
        case .unavailable: "macOS refused EDR; waiting for headroom"
        case .boosting:
            if let nits = status.nits {
                String(format: "%.2f× · ≈ %.0f nits", status.gain, nits)
            } else {
                String(format: "%.2f×", status.gain)
            }
        }
    }

    private static func describe(_ reason: SuspensionReason) -> String {
        switch reason {
        case .screenSaver: "screen saver"
        case .screenLocked: "screen locked"
        case .sessionInactive: "user switched"
        case .systemSleep: "sleeping"
        case .displaysAsleep: "display asleep"
        case .lowBattery: "low battery"
        case .lowPowerMode: "Low Power Mode"
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refresh()
        refreshLoginItem()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: Actions

    @objc private func toggleBoost() {
        controller.update { $0.isEnabled.toggle() }
    }

    @objc private func selectOverlay() {
        controller.update { $0.technique = .overlay }
    }

    @objc private func selectGamma() {
        controller.update { $0.technique = .gamma }
    }

    @objc private func selectBatteryThreshold(_ sender: NSMenuItem) {
        controller.update { $0.batteryThreshold = sender.representedObject as? Int }
    }

    @objc private func toggleLowPower() {
        controller.update { $0.pauseInLowPowerMode.toggle() }
    }

    @objc private func togglePlayback() {
        controller.update { $0.reduceDuringPlayback.toggle() }
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(LoginItem.state != .enabled)
        refreshLoginItem()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: """
                Uses your XDR display's HDR headroom to brighten everyday content. \
                Only public macOS APIs; macOS's own thermal protection stays in charge.

                Higher brightness costs battery and adds some LED wear. \
                Dark Mode keeps the panel cooler during long sessions.
                """,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}

// MARK: - Menu item views

private final class HeaderView: NSView {
    private let title = NSTextField(labelWithString: "Illuminate")
    private let detail = NSTextField(labelWithString: "")

    var subtitle: String {
        get { detail.stringValue }
        set { detail.stringValue = newValue }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 40))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class SliderView: NSView {
    var onChange: (Double) -> Void = { _ in }

    private let slider = NSSlider(value: 0.6, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let lowIcon = NSImageView(image: NSImage(systemSymbolName: "sun.min", accessibilityDescription: nil) ?? NSImage())
    private let highIcon = NSImageView(image: NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil) ?? NSImage())

    var level: Double {
        get { slider.doubleValue }
        set { if abs(slider.doubleValue - newValue) > 0.0001 { slider.doubleValue = newValue } }
    }

    var isEnabled: Bool {
        get { slider.isEnabled }
        set { slider.isEnabled = newValue }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel("Boost level")
        for icon in [lowIcon, highIcon] {
            icon.contentTintColor = .secondaryLabelColor
            icon.setAccessibilityElement(false)
        }
        let stack = NSStackView(views: [lowIcon, slider, highIcon])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed() {
        onChange(slider.doubleValue)
    }
}
