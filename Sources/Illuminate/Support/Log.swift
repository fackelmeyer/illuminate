import os

nonisolated enum Log {
    static let subsystem = "com.fackelmeyer.illuminate"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let gamma = Logger(subsystem: subsystem, category: "gamma")
    static let events = Logger(subsystem: subsystem, category: "events")
}
