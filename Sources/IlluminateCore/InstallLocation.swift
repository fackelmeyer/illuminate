/// Where the running app bundle lives, as far as login-item registration cares.
///
/// `SMAppService.mainApp` records the bundle's current path. Registering while the
/// app runs from the disk image or from Gatekeeper's randomised translocation path
/// leaves a login item that points nowhere once the image is ejected.
public enum InstallLocation: Equatable, Sendable {
    case applications
    case diskImage
    case translocated
    case other

    public init(bundlePath: String, homeDirectory: String) {
        let components = bundlePath.split(separator: "/").map(String.init)
        let home = homeDirectory.split(separator: "/").map(String.init)
        if components.contains("AppTranslocation") {
            self = .translocated
        } else if components.first == "Volumes" {
            self = .diskImage
        } else if components.first == "Applications"
                    || (components.starts(with: home) && components.dropFirst(home.count).first == "Applications") {
            self = .applications
        } else {
            self = .other
        }
    }

    public var canRegisterLoginItem: Bool {
        switch self {
        case .applications, .other: true
        case .diskImage, .translocated: false
        }
    }
}
