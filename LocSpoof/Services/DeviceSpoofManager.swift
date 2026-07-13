import Foundation
import CoreLocation
import Combine

/// Singleton managing all communication with connected iOS devices via shell commands.
/// Uses `devicectl` for iOS 17+ and `pymobiledevice3` for older iOS versions.
final class DeviceSpoofManager: ObservableObject {
    static let shared = DeviceSpoofManager()

    @Published var devices: [ConnectedDevice] = []
    @Published var selectedDevice: ConnectedDevice?
    @Published var simulationMode: SimulationMode = .idle
    @Published var currentSpoofedLocation: CLLocationCoordinate2D?
    @Published var currentHeading: Double = 0  // radians, 0 = North
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    @Published var statusMessage: String = "Ready"
    @Published var currentSpeed: Double = 0  // km/h
    @Published var simulationProgress: Double = 0.0  // 0.0 to 1.0 representing route completion
    @Published var antiDetectionEnabled: Bool = true  // adds micro-jitter and randomized timing loops
    @Published var showAdPopup: Bool = false  // gates spoofing for trial users

    var pendingSpoofAction: (() -> Void)? = nil
    private var simulationTask: Task<Void, Never>?
    private let commandQueue = DispatchQueue(label: "com.locspoof.commands", qos: .userInitiated)

    private init() {}

    /// Gates spoofing action behind an ad check if in trial mode
    func triggerSpoofAction(_ action: @escaping () -> Void) {
        if LicenseManager.shared.isTrialMode {
            self.pendingSpoofAction = action
            self.showAdPopup = true
        } else {
            action()
        }
    }

    // MARK: - Device Discovery

    /// Scan for connected devices using `devicectl` and `pymobiledevice3`
    func scanForDevices() {
        isScanning = true
        lastError = nil
        statusMessage = "Scanning for devices…"

        Task { @MainActor in
            var foundDevices: [ConnectedDevice] = []
            var seenUDIDs = Set<String>()

            // Try devicectl first (iOS 17+) — these are authoritative
            let devicectlResult = await runShellCommand(
                "/usr/bin/xcrun",
                arguments: ["devicectl", "list", "devices", "--json-output", "/tmp/locspoof_devices.json"]
            )

            if devicectlResult.exitCode == 0 {
                let parsed = parseDevicectlJSON()
                for device in parsed {
                    // Deduplicate by base UDID (strip any suffix)
                    let baseUDID = Self.baseUDID(device.id)
                    if !seenUDIDs.contains(baseUDID) {
                        seenUDIDs.insert(baseUDID)
                        foundDevices.append(device)
                    }
                }
            }

            // Also try pymobiledevice3 for older iOS devices
            let pyResult = await runShellCommand(
                "/usr/local/bin/pymobiledevice3",
                arguments: ["usbmux", "list", "--no-color"]
            )

            if pyResult.exitCode == 0 {
                let parsed = parsePymobiledevice3Output(pyResult.output)
                for device in parsed {
                    let baseUDID = Self.baseUDID(device.id)
                    if !seenUDIDs.contains(baseUDID) {
                        seenUDIDs.insert(baseUDID)
                        foundDevices.append(device)
                    }
                }
            }

            // Try scanning for Android devices via adb
            let adbResult = await runShellCommand(
                "/opt/homebrew/bin/adb",
                arguments: ["devices"]
            )
            if adbResult.exitCode == 0 {
                let androidDevices = await parseAdbDevicesOutput(adbResult.output)
                for device in androidDevices {
                    if !seenUDIDs.contains(device.id) {
                        seenUDIDs.insert(device.id)
                        foundDevices.append(device)
                    }
                }
            }

            self.devices = foundDevices
            if self.selectedDevice == nil, let first = foundDevices.first {
                self.selectedDevice = first
            }
            // If selected device disappeared, deselect
            if let sel = self.selectedDevice, !foundDevices.contains(where: { $0.id == sel.id }) {
                self.selectedDevice = foundDevices.first
            }
            self.isScanning = false
            self.statusMessage = foundDevices.isEmpty ? "No devices found" : "\(foundDevices.count) device(s) found"
        }
    }

    /// Extract the base UDID by removing network suffixes / dashes
    /// devicectl may append transport info; normalize to the core identifier.
    private static func baseUDID(_ udid: String) -> String {
        // UDIDs are typically 40 hex chars (pre-iPhone X) or UUID format (post).
        // Normalize: lowercase, strip common suffixes
        let cleaned = udid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // If it contains a dot or colon (network identifier suffix), take part before it
        if let dotIndex = cleaned.firstIndex(of: ".") {
            return String(cleaned[cleaned.startIndex..<dotIndex])
        }
        return cleaned
    }

    // MARK: - Location Spoofing

    /// Teleport: send a single coordinate to the device
    func teleportTo(_ coordinate: CLLocationCoordinate2D) {
        guard let device = selectedDevice else {
            lastError = "No device selected"
            return
        }

        stopSimulation()
        statusMessage = "Teleporting…"

        Task { @MainActor in
            let success = await sendLocation(coordinate, to: device)
            if success {
                currentSpoofedLocation = coordinate
                simulationMode = .teleported
                statusMessage = String(format: "Teleported to %.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
        }
    }

    /// Simulate movement along a series of coordinates with heading tracking
    func simulateRoute(_ coordinates: [CLLocationCoordinate2D], speedKmh: Double, mode: SimulationMode = .routeSimulation) {
        guard let device = selectedDevice else {
            lastError = "No device selected"
            return
        }
        guard coordinates.count >= 2 else {
            lastError = "Need at least 2 points"
            return
        }

        stopSimulation()
        simulationMode = mode
        currentSpeed = speedKmh
        simulationProgress = 0.0
        statusMessage = "Simulating route at \(Int(speedKmh)) km/h…"

        simulationTask = Task { @MainActor in
            let speedMps = speedKmh / 3.6
            let baseInterval: TimeInterval = 0.25

            // 1. Calculate total steps to measure exact progress
            var totalSteps = 0
            for i in 0..<(coordinates.count - 1) {
                let start = coordinates[i]
                let end = coordinates[i + 1]
                let segmentDistance = start.distance(to: end)
                let segmentDuration = segmentDistance / speedMps
                let steps = max(1, Int(segmentDuration / baseInterval))
                totalSteps += steps
            }
            totalSteps = max(1, totalSteps)

            var currentStep = 0

            // 2. Run simulation loop
            for i in 0..<(coordinates.count - 1) {
                if Task.isCancelled { break }

                let start = coordinates[i]
                let end = coordinates[i + 1]
                let segmentDistance = start.distance(to: end)
                let segmentDuration = segmentDistance / speedMps
                let steps = max(1, Int(segmentDuration / baseInterval))
                let segmentBearing = start.bearing(to: end)

                for step in 0...steps {
                    if Task.isCancelled { break }

                    let fraction = Double(step) / Double(steps)
                    let lat = start.latitude + (end.latitude - start.latitude) * fraction
                    let lon = start.longitude + (end.longitude - start.longitude) * fraction
                    let interpolated = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                    let success = await sendLocation(interpolated, to: device)
                    if success {
                        currentSpoofedLocation = interpolated
                        currentHeading = segmentBearing
                    }

                    // Update progress
                    if step > 0 {
                        currentStep += 1
                        simulationProgress = min(1.0, Double(currentStep) / Double(totalSteps))
                    }

                    if step < steps {
                        // Apply slight random sleep variance to prevent detection
                        let sleepTime = antiDetectionEnabled 
                            ? baseInterval + Double.random(in: -0.015...0.015) 
                            : baseInterval
                        try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                    }
                }
            }

            if !Task.isCancelled {
                simulationMode = .idle
                currentSpeed = 0
                simulationProgress = 1.0
                statusMessage = "Route simulation complete"
            }
        }
    }

    /// Move in a direction (joystick) — single step
    func moveInDirection(bearing: Double, distanceMeters: Double) {
        guard let current = currentSpoofedLocation ?? defaultLocation() else { return }
        let newCoord = current.offset(distance: distanceMeters, bearing: bearing)

        guard let device = selectedDevice else {
            lastError = "No device selected"
            return
        }

        Task { @MainActor in
            let success = await sendLocation(newCoord, to: device)
            if success {
                currentSpoofedLocation = newCoord
                currentHeading = bearing
                simulationMode = .joystick
                statusMessage = "Joystick active"
            }
        }
    }

    // MARK: - Stop / Reset

    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        simulationMode = .idle
        currentSpeed = 0
        statusMessage = "Simulation stopped"
    }

    func resetDeviceLocation() {
        guard let device = selectedDevice else {
            lastError = "No device selected"
            return
        }

        stopSimulation()
        statusMessage = "Resetting location…"

        Task { @MainActor in
            do {
                try await SpoofingEngine.shared.spoofer(for: device).clearLocation(for: device)
                currentSpoofedLocation = nil
                currentHeading = 0
                simulationMode = .idle
                statusMessage = "Location reset to real GPS"
            } catch {
                lastError = "Reset failed: \(error.localizedDescription)"
                statusMessage = "Reset failed"
            }
        }
    }

    // MARK: - Shell Command Execution

    private func sendLocation(_ coordinate: CLLocationCoordinate2D, to device: ConnectedDevice) async -> Bool {
        do {
            try await SpoofingEngine.shared.spoofer(for: device).sendLocation(
                coordinate,
                to: device,
                antiDetection: antiDetectionEnabled
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    struct ShellResult {
        let output: String
        let error: String
        let exitCode: Int32
    }

    private func runShellCommand(_ command: String, arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            commandQueue.async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                var env = ProcessInfo.processInfo.environment
                let existingPath = env["PATH"] ?? ""
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
                process.environment = env

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    continuation.resume(returning: ShellResult(
                        output: String(data: outputData, encoding: .utf8) ?? "",
                        error: String(data: errorData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    ))
                } catch {
                    continuation.resume(returning: ShellResult(
                        output: "",
                        error: error.localizedDescription,
                        exitCode: -1
                    ))
                }
            }
        }
    }

    // MARK: - Parsing Helpers

    private func parseDevicectlJSON() -> [ConnectedDevice] {
        var result: [ConnectedDevice] = []
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/locspoof_devices.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultObj = json["result"] as? [String: Any],
              let deviceList = resultObj["devices"] as? [[String: Any]]
        else { return [] }

        for entry in deviceList {
            guard let udid = entry["identifier"] as? String,
                  let props = entry["deviceProperties"] as? [String: Any],
                  let name = props["name"] as? String
            else { continue }

            let osVersion = (props["osVersionNumber"] as? String) ?? "17.0"
            let model = (props["productType"] as? String) ?? "iPhone"

            // Connection type: check connectionProperties.transportType
            var connType: DeviceConnectionType = .usb
            if let connProps = entry["connectionProperties"] as? [String: Any] {
                let transport = (connProps["transportType"] as? String)?.lowercased() ?? ""
                if transport.contains("network") || transport.contains("wifi") || transport.contains("local") {
                    connType = .wifi
                }
            }
            // Also detect by UDID pattern — network devices often have longer UUIDs with dashes
            if udid.contains("-") && udid.count > 24 && connType == .usb {
                // Heuristic: wired UDIDs for older devices are 40-char hex,
                // network connections via devicectl often use UUID with dashes
                // Only override if connectionProperties didn't set it
            }

            result.append(ConnectedDevice(
                id: udid, name: name, model: model,
                osVersion: osVersion, connectionType: connType, platform: .ios
            ))
        }
        return result
    }

    private func parsePymobiledevice3Output(_ output: String) -> [ConnectedDevice] {
        var result: [ConnectedDevice] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let components = trimmed.split(separator: " ", maxSplits: 4).map(String.init)
            guard components.count >= 4 else { continue }
            if components[0].lowercased() == "udid" || components[0].hasPrefix("-") { continue }

            // Detect connection type: check for "Network" or "WiFi" in the line
            let lineLC = trimmed.lowercased()
            let connType: DeviceConnectionType = (lineLC.contains("network") || lineLC.contains("wifi")) ? .wifi : .usb

            result.append(ConnectedDevice(
                id: components[0],
                name: components[1],
                model: components.count > 2 ? components[2] : "iPhone",
                osVersion: components.count > 3 ? components[3] : "16.0",
                connectionType: connType, platform: .ios
            ))
        }
        return result
    }

    private func parseAdbDevicesOutput(_ output: String) async -> [ConnectedDevice] {
        var result: [ConnectedDevice] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List") || trimmed.hasPrefix("*") { continue }
            
            // adb devices output is separated by tabs/spaces: <serial> <status>
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            
            let serial = parts[0]
            let status = parts[1]
            guard status == "device" else { continue }
            
            let connType: DeviceConnectionType = serial.contains(":") ? .wifi : .usb
            
            // Query details via adb shell getprop
            let modelResult = await runShellCommand("/opt/homebrew/bin/adb", arguments: ["-s", serial, "shell", "getprop", "ro.product.model"])
            let brandResult = await runShellCommand("/opt/homebrew/bin/adb", arguments: ["-s", serial, "shell", "getprop", "ro.product.brand"])
            let osResult = await runShellCommand("/opt/homebrew/bin/adb", arguments: ["-s", serial, "shell", "getprop", "ro.build.version.release"])
            
            let model = modelResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = brandResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let osVersion = osResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let cleanModel = model.isEmpty ? "Android Device" : model
            let cleanBrand = brand.isEmpty ? "Android" : brand.capitalized
            let cleanOS = osVersion.isEmpty ? "10.0" : osVersion
            
            result.append(ConnectedDevice(
                id: serial,
                name: "\(cleanBrand) \(cleanModel)",
                model: cleanModel,
                osVersion: cleanOS,
                connectionType: connType,
                platform: .android
            ))
        }
        return result
    }

    private func defaultLocation() -> CLLocationCoordinate2D? {
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
}

// MARK: - Dependency Manager

@MainActor
final class DependencyManager: ObservableObject {
    static let shared = DependencyManager()

    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = "Idle"
    @Published var installationError: String? = nil
    @Published var hasDependencies = false

    private let appSupportDir: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("LocSpoof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }()

    var pymobiledevice3Path: String {
        let venvPath = appSupportDir.appendingPathComponent("venv/bin/pymobiledevice3").path
        if FileManager.default.fileExists(atPath: venvPath) {
            return venvPath
        }
        return "/opt/homebrew/bin/pymobiledevice3"
    }

    var adbPath: String {
        let customPath = "/opt/homebrew/bin/adb"
        if FileManager.default.fileExists(atPath: customPath) {
            return customPath
        }
        let fallbackPath = "/usr/local/bin/adb"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return fallbackPath
        }
        return "adb"
    }

    func checkDependencies() async -> Bool {
        isChecking = true
        statusMessage = "Verifying toolchains..."
        
        let hasBrew = checkBrewInstalled()
        let hasAdb = checkAdbInstalled()
        let hasPymobiledevice3 = checkPymobiledevice3Installed()
        
        isChecking = false
        
        if hasAdb && hasPymobiledevice3 {
            hasDependencies = true
            statusMessage = "All dependencies satisfied."
            return true
        }
        
        hasDependencies = false
        statusMessage = "Dependencies missing."
        return false
    }

    func installDependencies() async {
        isInstalling = true
        installationError = nil
        progress = 0.0
        
        do {
            statusMessage = "Ensuring Homebrew is installed..."
            progress = 0.1
            if !checkBrewInstalled() {
                statusMessage = "Installing Homebrew (may take a few minutes)..."
                try await runInstallHomebrew()
            }
            
            statusMessage = "Ensuring Android Platform Tools are installed..."
            progress = 0.4
            if !checkAdbInstalled() {
                statusMessage = "Installing android-platform-tools..."
                try await runBrewInstall(cask: true, formula: "android-platform-tools")
            }
            
            statusMessage = "Configuring Python virtual environment..."
            progress = 0.7
            try await setupPythonVenvAndPymobiledevice3()
            
            progress = 1.0
            statusMessage = "Setup complete!"
            hasDependencies = true
            isInstalling = false
        } catch {
            progress = 0.0
            installationError = error.localizedDescription
            statusMessage = "Setup failed."
            isInstalling = false
            hasDependencies = false
        }
    }

    private func checkBrewInstalled() -> Bool {
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return brewPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func checkAdbInstalled() -> Bool {
        let adbPaths = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        if adbPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return true
        }
        return runCommandCheck(cmd: "which adb")
    }

    private func checkPymobiledevice3Installed() -> Bool {
        let path = appSupportDir.appendingPathComponent("venv/bin/pymobiledevice3").path
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
        return runCommandCheck(cmd: "which pymobiledevice3")
    }

    private func runCommandCheck(cmd: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runInstallHomebrew() async throws {
        let installCmd = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", installCmd]
        
        var env = ProcessInfo.processInfo.environment
        env["NONINTERACTIVE"] = "1"
        process.environment = env
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown Homebrew installation error."
                    continuation.resume(throwing: NSError(domain: "LocSpoof.Homebrew", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runBrewInstall(cask: Bool, formula: String) async throws {
        let brewBin = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
        
        var args = ["install"]
        if cask {
            args.append("--cask")
        }
        args.append(formula)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewBin)
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Brew install of \(formula) failed."
                    continuation.resume(throwing: NSError(domain: "LocSpoof.Brew", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func setupPythonVenvAndPymobiledevice3() async throws {
        let venvPath = appSupportDir.appendingPathComponent("venv").path
        
        let createVenvProcess = Process()
        createVenvProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        createVenvProcess.arguments = ["-m", "venv", venvPath]
        
        let errorPipe1 = Pipe()
        createVenvProcess.standardError = errorPipe1
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try createVenvProcess.run()
                createVenvProcess.waitUntilExit()
                if createVenvProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errMsg = String(data: errorPipe1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Python virtualenv setup failed."
                    continuation.resume(throwing: NSError(domain: "LocSpoof.PythonVenv", code: Int(createVenvProcess.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
        let pipBin = appSupportDir.appendingPathComponent("venv/bin/pip").path
        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: pipBin)
        installProcess.arguments = ["install", "--upgrade", "pymobiledevice3"]
        
        let errorPipe2 = Pipe()
        installProcess.standardError = errorPipe2
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try installProcess.run()
                installProcess.waitUntilExit()
                if installProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errMsg = String(data: errorPipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Failed to pip install pymobiledevice3."
                    continuation.resume(throwing: NSError(domain: "LocSpoof.PipInstall", code: Int(installProcess.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Spoofing Engine

@MainActor
protocol DeviceSpoofer {
    func sendLocation(_ coordinate: CLLocationCoordinate2D, to device: ConnectedDevice, antiDetection: Bool) async throws
    func clearLocation(for device: ConnectedDevice) async throws
}

@MainActor
final class SpoofingEngine {
    static let shared = SpoofingEngine()
    
    private let iosSpoofer = iOSDeviceSpoofer()
    private let androidSpoofer = AndroidDeviceSpoofer()
    
    private init() {}
    
    func spoofer(for device: ConnectedDevice) -> DeviceSpoofer {
        switch device.platform {
        case .ios:
            return iosSpoofer
        case .android:
            return androidSpoofer
        }
    }
}

@MainActor
final class iOSDeviceSpoofer: DeviceSpoofer {
    func sendLocation(_ coordinate: CLLocationCoordinate2D, to device: ConnectedDevice, antiDetection: Bool) async throws {
        var finalCoord = coordinate
        if antiDetection {
            let latOffset = Double.random(in: -0.000018...0.000018)
            let lonOffset = Double.random(in: -0.000018...0.000018)
            finalCoord = CLLocationCoordinate2D(
                latitude: coordinate.latitude + latOffset,
                longitude: coordinate.longitude + lonOffset
            )
        }
        
        let lat = String(format: "%.6f", finalCoord.latitude)
        let lon = String(format: "%.6f", finalCoord.longitude)
        
        if device.isiOS17OrLater {
            let result = try await ShellExecutor.run(
                "/usr/bin/xcrun",
                arguments: ["devicectl", "device", "simulate", "location", "coordinate",
                            "--device", device.id,
                            "--latitude=\(lat)",
                            "--longitude=\(lon)"]
            )
            if result.exitCode != 0 {
                let errMsg = result.error.isEmpty ? "devicectl failed to set location" : result.error
                throw NSError(domain: "LocSpoof.iOS", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
        } else {
            let pymobiledevice3Path = DependencyManager.shared.pymobiledevice3Path
            let result = try await ShellExecutor.run(
                pymobiledevice3Path,
                arguments: ["developer", "simulate-location", "set",
                            "--udid", device.id,
                            "--", lat, lon]
            )
            if result.exitCode != 0 {
                let errMsg = result.error.isEmpty ? "pymobiledevice3 failed to set location" : result.error
                throw NSError(domain: "LocSpoof.iOS", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
        }
    }
    
    func clearLocation(for device: ConnectedDevice) async throws {
        if device.isiOS17OrLater {
            let result = try await ShellExecutor.run(
                "/usr/bin/xcrun",
                arguments: ["devicectl", "device", "simulate", "location", "clear",
                            "--device", device.id]
            )
            if result.exitCode != 0 {
                let errMsg = result.error.isEmpty ? "devicectl failed to clear location" : result.error
                throw NSError(domain: "LocSpoof.iOS", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
        } else {
            let pymobiledevice3Path = DependencyManager.shared.pymobiledevice3Path
            let result = try await ShellExecutor.run(
                pymobiledevice3Path,
                arguments: ["developer", "simulate-location", "clear",
                            "--udid", device.id]
            )
            if result.exitCode != 0 {
                let errMsg = result.error.isEmpty ? "pymobiledevice3 failed to clear location" : result.error
                throw NSError(domain: "LocSpoof.iOS", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
        }
    }
}

@MainActor
final class AndroidDeviceSpoofer: DeviceSpoofer {
    func sendLocation(_ coordinate: CLLocationCoordinate2D, to device: ConnectedDevice, antiDetection: Bool) async throws {
        var finalCoord = coordinate
        if antiDetection {
            let latOffset = Double.random(in: -0.000018...0.000018)
            let lonOffset = Double.random(in: -0.000018...0.000018)
            finalCoord = CLLocationCoordinate2D(
                latitude: coordinate.latitude + latOffset,
                longitude: coordinate.longitude + lonOffset
            )
        }
        
        let lat = String(format: "%.6f", finalCoord.latitude)
        let lon = String(format: "%.6f", finalCoord.longitude)
        
        let adbPath = DependencyManager.shared.adbPath
        
        let _ = try? await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "appops", "set", "io.appium.settings", "android:mock_location", "allow"]
        )
        
        let _ = try? await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "am", "start-foreground-service",
                        "-e", "latitude", lat,
                        "-e", "longitude", lon,
                        "io.appium.settings/.LocationService"]
        )
        let _ = try? await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "am", "startservice",
                        "-e", "latitude", lat,
                        "-e", "longitude", lon,
                        "io.appium.settings/.LocationService"]
        )
        
        let result = try await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "am", "broadcast",
                        "-a", "send.mock",
                        "-e", "lat", lat,
                        "-e", "lon", lon]
        )
        
        if result.exitCode != 0 {
            let errMsg = result.error.isEmpty ? "adb failed to broadcast location to mock app" : result.error
            throw NSError(domain: "LocSpoof.Android", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
    }
    
    func clearLocation(for device: ConnectedDevice) async throws {
        let adbPath = DependencyManager.shared.adbPath
        
        let _ = try await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "am", "stopservice", "io.appium.settings/.LocationService"]
        )
        let _ = try await ShellExecutor.run(
            adbPath,
            arguments: ["-s", device.id, "shell", "am", "broadcast", "-a", "stop.mock"]
        )
    }
}

// MARK: - Shell Executor

final class ShellExecutor {
    struct Result {
        let output: String
        let error: String
        let exitCode: Int32
    }
    
    static func run(_ command: String, arguments: [String]) async throws -> Result {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(existingPath)"
            process.environment = env
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                continuation.resume(returning: Result(
                    output: String(data: outData, encoding: .utf8) ?? "",
                    error: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                ))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
