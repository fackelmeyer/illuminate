import Foundation
import IOKit.ps
import IlluminateCore

/// Publishes the current `PowerStatus` whenever the power source,
/// battery level or Low Power Mode changes.
final class PowerMonitor {
    var onChange: (PowerStatus) -> Void = { _ in }

    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObservation: NSObjectProtocol?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        lowPowerObservation = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        publish()
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        if let lowPowerObservation { NotificationCenter.default.removeObserver(lowPowerObservation) }
        lowPowerObservation = nil
    }

    var current: PowerStatus {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let isOnBattery = (IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String) == kIOPMBatteryPowerKey
        var percent: Int?
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            percent = capacity * 100 / maximum
        }
        return PowerStatus(
            isOnBattery: isOnBattery,
            batteryPercent: percent,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    fileprivate func publish() {
        onChange(current)
    }
}

private nonisolated func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.publish() }
}
