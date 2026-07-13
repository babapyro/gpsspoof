import SwiftUI

@main
struct LocSpoofApp: App {
    @StateObject private var licenseManager = LicenseManager.shared
    @StateObject private var deviceManager = DeviceSpoofManager.shared
    @StateObject private var mapViewModel = MapViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if licenseManager.isLicensed {
                    ContentView()
                        .environmentObject(deviceManager)
                        .environmentObject(mapViewModel)
                        .transition(.opacity)
                } else {
                    LicenseView(licenseManager: licenseManager)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: licenseManager.isLicensed)
            .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
