/// Why the boost is currently paused. Several can hold at once.
public enum SuspensionReason: String, Hashable, Sendable, CaseIterable {
    case screenSaver
    case screenLocked
    case sessionInactive
    case systemSleep
    case displaysAsleep
    case lowBattery
    case lowPowerMode
}

/// The set of active suspension reasons.
///
/// Modelled as a set rather than a flag so that clearing one reason
/// (the screen saver stopping) cannot resume the boost while another
/// (the lock screen) still holds.
public struct SuspensionState: Equatable, Sendable {
    public enum Transition: Equatable, Sendable {
        case unchanged
        case suspended
        case resumed
    }

    public private(set) var reasons: Set<SuspensionReason> = []

    public init() {}

    public var isSuspended: Bool { !reasons.isEmpty }

    /// The reason to show the user: the first active one in declaration order,
    /// so the menu stays stable while several reasons hold.
    public var primaryReason: SuspensionReason? {
        SuspensionReason.allCases.first(where: reasons.contains)
    }

    @discardableResult
    public mutating func insert(_ reason: SuspensionReason) -> Transition {
        let wasSuspended = isSuspended
        reasons.insert(reason)
        return wasSuspended ? .unchanged : .suspended
    }

    @discardableResult
    public mutating func remove(_ reason: SuspensionReason) -> Transition {
        guard reasons.remove(reason) != nil else { return .unchanged }
        return isSuspended ? .unchanged : .resumed
    }

    @discardableResult
    public mutating func set(_ reason: SuspensionReason, active: Bool) -> Transition {
        active ? insert(reason) : remove(reason)
    }
}
