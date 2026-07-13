mod dependency_manager;
mod license_manager;
mod spoof_engine;

use dependency_manager::{DependencyManager, DependencyStatus};
use license_manager::{LicenseManager, LicenseStatus};
use spoof_engine::{ConnectedDevice, SpoofEngine};
use tauri::Emitter;

#[tauri::command]
fn check_dependencies() -> Result<DependencyStatus, String> {
    let dm = DependencyManager::new();
    Ok(dm.check_all())
}

#[tauri::command]
fn install_dependencies(app: tauri::AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn(async move {
        let dm = DependencyManager::new();
        let app_clone = app.clone();
        
        #[derive(Clone, serde::Serialize)]
        struct ProgressPayload {
            progress: f32,
            message: String,
        }

        let res = dm.install(move |progress, message| {
            let _ = app_clone.emit("dependency-progress", ProgressPayload {
                progress,
                message: message.to_string(),
            });
        });

        #[derive(Clone, serde::Serialize)]
        struct CompletionPayload {
            success: bool,
            error: Option<String>,
        }

        match res {
            Ok(_) => {
                let _ = app.emit("dependency-complete", CompletionPayload {
                    success: true,
                    error: None,
                });
            }
            Err(e) => {
                let _ = app.emit("dependency-complete", CompletionPayload {
                    success: false,
                    error: Some(e),
                });
            }
        }
    });
    Ok(())
}

#[tauri::command]
fn get_license_status() -> Result<LicenseStatus, String> {
    let lm = LicenseManager::new();
    Ok(lm.get_status())
}

#[tauri::command]
fn start_license_trial() -> Result<LicenseStatus, String> {
    let lm = LicenseManager::new();
    lm.start_trial()
}

#[tauri::command]
fn activate_license(key: String) -> Result<LicenseStatus, String> {
    let lm = LicenseManager::new();
    lm.activate(&key)
}

#[tauri::command]
fn deactivate_license() -> Result<LicenseStatus, String> {
    let lm = LicenseManager::new();
    Ok(lm.deactivate())
}

#[tauri::command]
fn scan_devices() -> Result<Vec<ConnectedDevice>, String> {
    let se = SpoofEngine::new();
    se.scan_devices()
}

#[tauri::command]
fn teleport_device(device: ConnectedDevice, lat: f64, lon: f64, anti_detection: bool) -> Result<(), String> {
    let se = SpoofEngine::new();
    se.teleport(&device, lat, lon, anti_detection)
}

#[tauri::command]
fn reset_device_location(device: ConnectedDevice) -> Result<(), String> {
    let se = SpoofEngine::new();
    se.reset_location(&device)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            check_dependencies,
            install_dependencies,
            get_license_status,
            start_license_trial,
            activate_license,
            deactivate_license,
            scan_devices,
            teleport_device,
            reset_device_location
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
