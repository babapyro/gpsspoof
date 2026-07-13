use std::process::{Command, Output};
use std::path::{Path, PathBuf};
use serde::{Serialize, Deserialize};
use std::fs;
use crate::dependency_manager::DependencyManager;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum Platform {
    #[serde(rename = "ios")]
    Ios,
    #[serde(rename = "android")]
    Android,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub enum ConnectionType {
    #[serde(rename = "usb")]
    Usb,
    #[serde(rename = "wifi")]
    Wifi,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ConnectedDevice {
    pub id: String,
    pub name: String,
    pub model: String,
    pub os_version: String,
    pub connection_type: ConnectionType,
    pub platform: Platform,
}

pub struct SpoofEngine {
    dependency_manager: DependencyManager,
    app_dir: PathBuf,
}

impl SpoofEngine {
    pub fn new() -> Self {
        let dm = DependencyManager::new();
        let app_dir = if let Some(proj_dirs) = directories::ProjectDirs::from("com", "pyrollc", "LocSpoof") {
            proj_dirs.data_dir().to_path_buf()
        } else {
            PathBuf::from("./.locspoof")
        };
        Self { dependency_manager: dm, app_dir }
    }

    /// Discovers connected devices
    pub fn scan_devices(&self) -> Result<Vec<ConnectedDevice>, String> {
        let mut devices = Vec::new();

        // 1. Scan iOS Devices using pymobiledevice3
        if let Ok(ios_devs) = self.scan_ios_devices() {
            devices.extend(ios_devs);
        }

        // 2. Scan Android Devices using adb
        if let Ok(android_devs) = self.scan_android_devices() {
            devices.extend(android_devs);
        }

        Ok(devices)
    }

    fn scan_ios_devices(&self) -> Result<Vec<ConnectedDevice>, String> {
        let pymobiledevice3 = self.dependency_manager.get_pymobiledevice3_path();
        
        let output = Command::new(&pymobiledevice3)
            .args(&["usbmux", "list", "--no-color"])
            .output();

        let output = match output {
            Ok(out) => out,
            Err(_) => return Err("pymobiledevice3 not installed or not in PATH".to_string()),
        };

        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).to_string());
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut devices = Vec::new();

        for line in stdout.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with("UDID") || line.starts_with("-") {
                continue;
            }

            // Output format: <udid> <name> <model> <os_version> <conn_type>
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let id = parts[0].to_string();
                let name = parts[1].to_string();
                let model = parts[2].to_string();
                let os_version = parts[3].to_string();
                
                let line_lc = line.to_lowercase();
                let connection_type = if line_lc.contains("network") || line_lc.contains("wifi") {
                    ConnectionType::Wifi
                } else {
                    ConnectionType::Usb
                };

                devices.push(ConnectedDevice {
                    id,
                    name,
                    model,
                    os_version,
                    connection_type,
                    platform: Platform::Ios,
                });
            }
        }

        Ok(devices)
    }

    fn scan_android_devices(&self) -> Result<Vec<ConnectedDevice>, String> {
        let adb = self.dependency_manager.get_adb_path();
        
        let output = Command::new(&adb)
            .arg("devices")
            .output();

        let output = match output {
            Ok(out) => out,
            Err(_) => return Err("ADB tool not installed or not found".to_string()),
        };

        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).to_string());
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut devices = Vec::new();

        for line in stdout.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with("List of devices") || line.starts_with("*") {
                continue;
            }

            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let id = parts[0].to_string();
                let status = parts[1];
                if status != "device" {
                    // Skip unauthorized or offline devices
                    continue;
                }

                let connection_type = if id.contains(":") {
                    ConnectionType::Wifi
                } else {
                    ConnectionType::Usb
                };

                // Query Android specific model and OS info
                let model = self.run_adb_getprop(&id, "ro.product.model").unwrap_or_else(|_| "Android Device".to_string());
                let brand = self.run_adb_getprop(&id, "ro.product.brand").unwrap_or_else(|_| "Android".to_string());
                let os_version = self.run_adb_getprop(&id, "ro.build.version.release").unwrap_or_else(|_| "10.0".to_string());

                devices.push(ConnectedDevice {
                    id,
                    name: format!("{} {}", brand.to_uppercase(), model),
                    model,
                    os_version,
                    connection_type,
                    platform: Platform::Android,
                });
            }
        }

        Ok(devices)
    }

    fn run_adb_getprop(&self, serial: &str, prop: &str) -> Result<String, String> {
        let adb = self.dependency_manager.get_adb_path();
        let output = Command::new(&adb)
            .args(&["-s", serial, "shell", "getprop", prop])
            .output()
            .map_err(|e| e.to_string())?;

        let val = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if val.is_empty() {
            Err("Empty property".to_string())
        } else {
            Ok(val)
        }
    }

    /// Set mock GPS coordinate on device
    pub fn teleport(&self, device: &ConnectedDevice, lat: f64, lon: f64, anti_detection: bool) -> Result<(), String> {
        let mut final_lat = lat;
        let mut final_lon = lon;

        // Apply micro-jitter (anti-detection)
        if anti_detection {
            // Let's implement a simple pseudorandom offset based on system time
            let duration = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let seed = duration.as_nanos();
            let offset_lat = (((seed % 1000) as f64 - 500.0) / 500.0) * 0.000015;
            let offset_lon = ((((seed / 1000) % 1000) as f64 - 500.0) / 500.0) * 0.000015;
            
            final_lat += offset_lat;
            final_lon += offset_lon;
        }

        match device.platform {
            Platform::Ios => self.teleport_ios(&device.id, final_lat, final_lon),
            Platform::Android => self.teleport_android(&device.id, final_lat, final_lon),
        }
    }

    fn teleport_ios(&self, udid: &str, lat: f64, lon: f64) -> Result<(), String> {
        let pymobiledevice3 = self.dependency_manager.get_pymobiledevice3_path();
        
        let lat_str = format!("{:.6}", lat);
        let lon_str = format!("{:.6}", lon);

        // Under Windows, we mount the Developer Disk Image and set simulate location
        let output = Command::new(&pymobiledevice3)
            .args(&[
                "developer",
                "simulate-location",
                "set",
                "--udid",
                udid,
                "--",
                &lat_str,
                &lon_str,
            ])
            .output();

        let output = match output {
            Ok(out) => out,
            Err(e) => return Err(format!("Failed to run pymobiledevice3: {}", e)),
        };

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(Self::parse_ios_error(&stderr));
        }

        Ok(())
    }

    fn teleport_android(&self, serial: &str, lat: f64, lon: f64) -> Result<(), String> {
        let adb = self.dependency_manager.get_adb_path();
        let lat_str = format!("{:.6}", lat);
        let lon_str = format!("{:.6}", lon);

        // 1. Ensure Appium settings APK is installed
        self.ensure_appium_settings_installed(serial)?;

        // 2. Grant Mock Location permission to Settings App
        let _ = Command::new(&adb)
            .args(&["-s", serial, "shell", "appops", "set", "io.appium.settings", "android:mock_location", "allow"])
            .status();

        // 3. Start foreground mock location service with coordinate extras
        let status = Command::new(&adb)
            .args(&[
                "-s", serial,
                "shell", "am", "start-foreground-service",
                "-e", "latitude", &lat_str,
                "-e", "longitude", &lon_str,
                "io.appium.settings/.LocationService",
            ])
            .output();

        // Fail-safe for Android SDK < 26 which does not support start-foreground-service
        if let Ok(ref out) = status {
            if !out.status.success() {
                let _ = Command::new(&adb)
                    .args(&[
                        "-s", serial,
                        "shell", "am", "startservice",
                        "-e", "latitude", &lat_str,
                        "-e", "longitude", &lon_str,
                        "io.appium.settings/.LocationService",
                    ])
                    .status();
            }
        }

        // 4. Send Broadcast Mock Event
        let output = Command::new(&adb)
            .args(&[
                "-s", serial,
                "shell", "am", "broadcast",
                "-a", "send.mock",
                "-e", "lat", &lat_str,
                "-e", "lon", &lon_str,
            ])
            .output();

        let output = match output {
            Ok(out) => out,
            Err(e) => return Err(format!("Failed to execute adb spoof command: {}", e)),
        };

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(Self::parse_android_error(&stderr));
        }

        Ok(())
    }

    /// Reset location to native GPS
    pub fn reset_location(&self, device: &ConnectedDevice) -> Result<(), String> {
        match device.platform {
            Platform::Ios => {
                let pymobiledevice3 = self.dependency_manager.get_pymobiledevice3_path();
                let output = Command::new(&pymobiledevice3)
                    .args(&["developer", "simulate-location", "clear", "--udid", &device.id])
                    .output();

                match output {
                    Ok(out) if out.status.success() => Ok(()),
                    Ok(out) => Err(Self::parse_ios_error(&String::from_utf8_lossy(&out.stderr))),
                    Err(e) => Err(format!("Failed to run reset: {}", e)),
                }
            }
            Platform::Android => {
                let adb = self.dependency_manager.get_adb_path();
                // Stop service and broadcast mock stop
                let _ = Command::new(&adb)
                    .args(&["-s", &device.id, "shell", "am", "stopservice", "io.appium.settings/.LocationService"])
                    .status();

                let output = Command::new(&adb)
                    .args(&["-s", &device.id, "shell", "am", "broadcast", "-a", "stop.mock"])
                    .output();

                match output {
                    Ok(out) if out.status.success() => Ok(()),
                    Ok(out) => Err(Self::parse_android_error(&String::from_utf8_lossy(&out.stderr))),
                    Err(e) => Err(format!("Failed to clear android location: {}", e)),
                }
            }
        }
    }

    fn ensure_appium_settings_installed(&self, serial: &str) -> Result<(), String> {
        let adb = self.dependency_manager.get_adb_path();
        
        // Check if installed
        let check = Command::new(&adb)
            .args(&["-s", serial, "shell", "pm", "list", "packages", "io.appium.settings"])
            .output();

        if let Ok(out) = check {
            let stdout = String::from_utf8_lossy(&out.stdout);
            if stdout.contains("package:io.appium.settings") {
                return Ok(()); // Already installed
            }
        }

        // Missing. Let's download the APK into local storage and install it
        let apk_path = self.app_dir.join("settings_apk-debug.apk");
        
        if !apk_path.exists() {
            let apk_url = "https://github.com/appium/io.appium.settings/releases/download/3.4.0/settings_apk-debug.apk";
            let response = ureq::get(apk_url)
                .call()
                .map_err(|e| format!("Failed to download Appium Mock Settings helper APK: {}", e))?;

            let mut reader = response.into_reader();
            let mut file = fs::File::create(&apk_path).map_err(|e| format!("Failed to create local APK file: {}", e))?;
            std::io::copy(&mut reader, &mut file).map_err(|e| format!("Failed to write local APK file: {}", e))?;
        }

        // Install it on the device
        let install_status = Command::new(&adb)
            .args(&["-s", serial, "install", "-r", &apk_path.to_string_lossy()])
            .output();

        match install_status {
            Ok(out) if out.status.success() => Ok(()),
            Ok(out) => {
                let err = String::from_utf8_lossy(&out.stderr);
                Err(format!("Auto-onboarding helper app failed to install on Android device: {}", err))
            }
            Err(e) => Err(format!("Auto-installer ADB execution error: {}", e)),
        }
    }

    // Friendly error parsing

    fn parse_ios_error(err: &str) -> String {
        let err_lc = err.to_lowercase();
        if err_lc.contains("pairing") || err_lc.contains("lockdown") {
            "iOS Trust Required: Please tap 'Trust This Computer' on your iPhone screen and enter passcode.".to_string()
        } else if err_lc.contains("developer mode") {
            "Developer Mode Disabled: On iOS 16+, you must enable Developer Mode under Settings -> Privacy & Security -> Developer Mode and restart your iPhone.".to_string()
        } else if err_lc.contains("mountererror") || err_lc.contains("mount") || err_lc.contains("disk image") {
            "Developer Disk Image missing: iOS requires Developer Disk Image (DDI) to mock location. Please mount via Xcode or check your device internet connection.".to_string()
        } else if err_lc.contains("lock") {
            "iPhone Locked: Please unlock your iPhone screen.".to_string()
        } else if err_lc.contains("not found") || err_lc.contains("no device") {
            "Device not found. Please reconnect the lightning/USB-C cable.".to_string()
        } else {
            format!("iOS Engine Error: {}", err)
        }
    }

    fn parse_android_error(err: &str) -> String {
        let err_lc = err.to_lowercase();
        if err_lc.contains("unauthorized") {
            "Android Debugging Unauthorized: Please check your phone screen and check 'Always allow from this computer' then click Allow USB Debugging.".to_string()
        } else if err_lc.contains("mock") {
            "Mock Location Blocked: Make sure Mock Location app is allowed for 'Appium Settings' in Android Developer Options.".to_string()
        } else if err_lc.contains("device not found") {
            "Android Device Disconnected. Please check connection.".to_string()
        } else {
            format!("Android Engine Error: {}", err)
        }
    }
}
