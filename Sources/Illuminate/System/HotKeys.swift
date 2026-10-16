import Carbon.HIToolbox
import os

/// Global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys need neither Accessibility permission nor an event tap,
/// and they work inside the App Sandbox.
final class HotKeys {
    nonisolated enum Action: UInt32, CaseIterable, Sendable {
        case toggle = 1
        case increase
        case decrease

        /// ⌃⌥⌘I toggles, ⌃⌥⌘↑ / ↓ step the boost.
        var keyCode: Int {
            switch self {
            case .toggle: kVK_ANSI_I
            case .increase: kVK_UpArrow
            case .decrease: kVK_DownArrow
            }
        }
    }

    var onAction: (Action) -> Void = { _ in }

    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private nonisolated static let signature: OSType = 0x494C_554D   // 'ILUM'

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &eventType, context, &handler)
        guard status == noErr else {
            Log.app.error("InstallEventHandler failed: \(status)")
            return
        }
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for action in Action.allCases {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let result = RegisterEventHotKey(UInt32(action.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                references.append(reference)
            } else {
                Log.app.error("Hotkey \(action.rawValue) unavailable: \(result)")
            }
        }
    }

    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    fileprivate func handle(_ action: Action) {
        onAction(action)
    }

    /// Reads the hotkey ID off the Carbon event. Pure C, so it runs before the hop to the main actor.
    fileprivate nonisolated static func action(for event: EventRef?) -> Action? {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == signature else { return nil }
        return Action(rawValue: id.id)
    }
}

private nonisolated func hotKeyPressed(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context, let action = HotKeys.action(for: event) else { return OSStatus(eventNotHandledErr) }
    let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { hotKeys.handle(action) }
    return noErr
}
