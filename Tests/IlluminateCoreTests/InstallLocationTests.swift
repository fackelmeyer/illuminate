import Testing
@testable import IlluminateCore

@Suite struct InstallLocationTests {
    @Test(arguments: [
        "/Applications/Illuminate.app",
        "/Applications/Utilities/Illuminate.app",
        "/Users/jonas/Applications/Illuminate.app",
    ])
    func `applications folders are installed`(path: String) {
        let location = InstallLocation(bundlePath: path, homeDirectory: "/Users/jonas")
        #expect(location == .applications)
        #expect(location.canRegisterLoginItem)
    }

    @Test func `running from the disk image is not installed`() {
        let location = InstallLocation(bundlePath: "/Volumes/Illuminate/Illuminate.app", homeDirectory: "/Users/jonas")
        #expect(location == .diskImage)
        #expect(location.canRegisterLoginItem == false)
    }

    @Test func `Gatekeeper translocation is not installed`() {
        let path = "/private/var/folders/xy/T/AppTranslocation/1234-ABCD/d/Illuminate.app"
        let location = InstallLocation(bundlePath: path, homeDirectory: "/Users/jonas")
        #expect(location == .translocated)
        #expect(location.canRegisterLoginItem == false)
    }

    @Test func `a development build can still register`() {
        let location = InstallLocation(bundlePath: "/Users/jonas/Development/illuminate/build/Illuminate.app", homeDirectory: "/Users/jonas")
        #expect(location == .other)
        #expect(location.canRegisterLoginItem)
    }

    @Test func `similar prefixes are not mistaken for Applications`() {
        let location = InstallLocation(bundlePath: "/ApplicationsBackup/Illuminate.app", homeDirectory: "/Users/jonas")
        #expect(location == .other)
    }
}
