use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs::{self, File};
use std::io::{self, copy};
use directories::ProjectDirs;
use zip::ZipArchive;

#[derive(serde::Serialize, Clone, Debug)]
pub struct DependencyStatus {
    pub python_installed: bool,
    pub pymobiledevice3_installed: bool,
    pub adb_installed: bool,
    pub status_message: String,
}

pub struct DependencyManager {
    app_dir: PathBuf,
}

impl DependencyManager {
    pub fn new() -> Self {
        let app_dir = if let Some(proj_dirs) = ProjectDirs::from("com", "pyrollc", "LocSpoof") {
            proj_dirs.data_dir().to_path_buf()
        } else {
            PathBuf::from("./.locspoof")
        };
        fs::create_dir_all(&app_dir).ok();
        Self { app_dir }
    }

    pub fn get_adb_path(&self) -> PathBuf {
        // First check standard PATH
        if check_command_in_path("adb") {
            return PathBuf::from("adb");
        }

        // Check our local storage
        let local_adb = self.app_dir.join("bin").join("platform-tools").join(if cfg!(windows) { "adb.exe" } else { "adb" });
        if local_adb.exists() {
            return local_adb;
        }

        // Windows standard directories
        if cfg!(windows) {
            let app_data = std::env::var("LOCALAPPDATA").unwrap_or_default();
            let paths = [
                format!("{}\\Android\\Sdk\\platform-tools\\adb.exe", app_data),
                "C:\\Program Files (x86)\\Android\\android-sdk\\platform-tools\\adb.exe".to_string(),
            ];
            for path in &paths {
                if Path::new(path).exists() {
                    return PathBuf::from(path);
                }
            }
        } else {
            // macOS standard directories
            let home = std::env::var("HOME").unwrap_or_default();
            let paths = [
                format!("{}/Library/Android/sdk/platform-tools/adb", home),
                "/opt/homebrew/bin/adb".to_string(),
                "/usr/local/bin/adb".to_string(),
            ];
            for path in &paths {
                if Path::new(path).exists() {
                    return PathBuf::from(path);
                }
            }
        }

        PathBuf::from("adb")
    }

    pub fn get_pymobiledevice3_path(&self) -> PathBuf {
        // Check if pymobiledevice3 is in path
        if check_command_in_path("pymobiledevice3") {
            return PathBuf::from("pymobiledevice3");
        }

        // Check python environment scripts folder
        if cfg!(windows) {
            // Check in AppData local python scripts
            if let Ok(app_data) = std::env::var("LOCALAPPDATA") {
                let python_dir = Path::new(&app_data).join("Programs").join("Python");
                if python_dir.exists() {
                    if let Ok(entries) = fs::read_dir(python_dir) {
                        for entry in entries.flatten() {
                            let script_path = entry.path().join("Scripts").join("pymobiledevice3.exe");
                            if script_path.exists() {
                                return script_path;
                            }
                        }
                    }
                }
            }
        } else {
            let home = std::env::var("HOME").unwrap_or_default();
            let script_path = Path::new(&home).join(".local").join("bin").join("pymobiledevice3");
            if script_path.exists() {
                return script_path;
            }
        }

        PathBuf::from("pymobiledevice3")
    }

    pub fn check_all(&self) -> DependencyStatus {
        let python_installed = self.check_python();
        let pymobiledevice3_installed = self.check_pymobiledevice3();
        let adb_installed = self.check_adb();

        let status_message = if python_installed && pymobiledevice3_installed && adb_installed {
            "All dependencies verified and ready.".to_string()
        } else {
            "Dependencies missing. Setup required.".to_string()
        };

        DependencyStatus {
            python_installed,
            pymobiledevice3_installed,
            adb_installed,
            status_message,
        }
    }

    fn check_python(&self) -> bool {
        check_command_in_path("python") || check_command_in_path("python3")
    }

    fn check_pymobiledevice3(&self) -> bool {
        let p = self.get_pymobiledevice3_path();
        if p.to_string_lossy() == "pymobiledevice3" {
            check_command_in_path("pymobiledevice3")
        } else {
            p.exists()
        }
    }

    fn check_adb(&self) -> bool {
        let p = self.get_adb_path();
        if p.to_string_lossy() == "adb" {
            check_command_in_path("adb")
        } else {
            p.exists()
        }
    }

    pub fn install<F>(&self, progress: F) -> Result<(), String>
    where
        F: Fn(f32, &str) + Send + Sync + 'static,
    {
        progress(0.1, "Checking python installation...");
        if !self.check_python() {
            progress(0.15, "Python missing. Installing Python...");
            self.install_python(&progress)?;
        }

        progress(0.4, "Python environment ready. Checking pip/pymobiledevice3...");
        if !self.check_pymobiledevice3() {
            progress(0.5, "Installing pymobiledevice3...");
            self.install_pymobiledevice3(&progress)?;
        }

        progress(0.7, "pymobiledevice3 verified. Checking Android platform-tools...");
        if !self.check_adb() {
            progress(0.8, "Downloading and installing Android platform-tools...");
            self.install_adb(&progress)?;
        }

        progress(1.0, "All dependencies successfully installed!");
        Ok(())
    }

    fn install_python<F>(&self, progress: &F) -> Result<(), String>
    where
        F: Fn(f32, &str) + Send + Sync + 'static,
    {
        if cfg!(windows) {
            // Windows winget install
            progress(0.2, "Executing winget to install Python 3...");
            let status = Command::new("powershell")
                .args(&[
                    "-NoProfile",
                    "-Command",
                    "winget install -e --id Python.Python.3 --silent --accept-package-agreements --accept-source-agreements",
                ])
                .status();

            if let Ok(exit) = status {
                if exit.success() {
                    progress(0.35, "Python installed successfully via winget.");
                    return Ok(());
                }
            }

            // Fallback: Download python installer from python.org
            progress(0.2, "winget failed. Downloading Python installer directly...");
            let py_url = "https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe";
            let dest_path = self.app_dir.join("python_installer.exe");
            
            download_file(py_url, &dest_path)?;

            progress(0.3, "Running Python installer silently (may request UAC)...");
            let install_status = Command::new(&dest_path)
                .args(&["/quiet", "InstallAllUsers=1", "PrependPath=1"])
                .status();

            // Cleanup installer
            fs::remove_file(dest_path).ok();

            if let Ok(exit) = install_status {
                if exit.success() {
                    progress(0.35, "Python installed successfully via manual installer.");
                    Ok(())
                } else {
                    Err("Python installation exited with non-zero status. Please install Python manually.".to_string())
                }
            } else {
                Err("Failed to start Python installer. Please run as Administrator.".to_string())
            }
        } else {
            // macOS Homebrew install
            progress(0.2, "Executing brew to install python3...");
            let status = Command::new("brew")
                .args(&["install", "python3"])
                .status();

            if let Ok(exit) = status {
                if exit.success() {
                    progress(0.35, "Python 3 installed successfully via brew.");
                    Ok(())
                } else {
                    Err("Brew install python3 failed. Please run 'brew install python3' in your terminal.".to_string())
                }
            } else {
                Err("Homebrew 'brew' command not found. Please install Homebrew or Python manually.".to_string())
            }
        }
    }

    fn install_pymobiledevice3<F>(&self, progress: &F) -> Result<(), String>
    where
        F: Fn(f32, &str) + Send + Sync + 'static,
    {
        let py_cmd = if check_command_in_path("python3") { "python3" } else { "python" };

        progress(0.55, "Upgrading pip and installing pymobiledevice3...");
        
        // Windows path issues - sometimes script directory is not in Path yet, try calling python module pip directly
        let status = Command::new(py_cmd)
            .args(&["-m", "pip", "install", "--upgrade", "pip"])
            .status();

        if let Err(e) = status {
            return Err(format!("Failed to run python -m pip: {}", e));
        }

        let status2 = Command::new(py_cmd)
            .args(&["-m", "pip", "install", "pymobiledevice3"])
            .status();

        match status2 {
            Ok(exit) if exit.success() => {
                progress(0.65, "pymobiledevice3 package installed.");
                Ok(())
            }
            _ => Err("Failed to install pymobiledevice3 package via pip. Try running 'pip install pymobiledevice3' manually.".to_string()),
        }
    }

    fn install_adb<F>(&self, progress: &F) -> Result<(), String>
    where
        F: Fn(f32, &str) + Send + Sync + 'static,
    {
        let url = if cfg!(windows) {
            "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
        } else {
            "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
        };

        let bin_dir = self.app_dir.join("bin");
        fs::create_dir_all(&bin_dir).ok();
        let zip_path = bin_dir.join("platform-tools.zip");

        progress(0.82, "Downloading Android platform-tools...");
        download_file(url, &zip_path)?;

        progress(0.9, "Extracting platform-tools zip...");
        let file = File::open(&zip_path).map_err(|e| format!("Failed to open downloaded zip: {}", e))?;
        let mut archive = ZipArchive::new(file).map_err(|e| format!("Zip parse error: {}", e))?;

        for i in 0..archive.len() {
            let mut file = archive.by_index(i).map_err(|e| format!("Zip read file error: {}", e))?;
            let outpath = match file.enclosed_name() {
                Some(path) => bin_dir.join(path),
                None => continue,
            };

            if (*file.name()).ends_with('/') {
                fs::create_dir_all(&outpath).ok();
            } else {
                if let Some(p) = outpath.parent() {
                    if !p.exists() {
                        fs::create_dir_all(&p).ok();
                    }
                }
                let mut outfile = File::create(&outpath).map_err(|e| format!("Create file error in extraction: {}", e))?;
                copy(&mut file, &mut outfile).map_err(|e| format!("Write file error in extraction: {}", e))?;
            }

            // Set executable permission on Unix-like systems
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if outpath.ends_with("adb") || outpath.ends_with("fastboot") {
                    fs::set_permissions(&outpath, std::fs::Permissions::from_mode(0o755)).ok();
                }
            }
        }

        // Clean up zip
        fs::remove_file(zip_path).ok();
        progress(0.98, "Platform-tools extraction finished.");
        Ok(())
    }
}

// Helpers

fn check_command_in_path(cmd: &str) -> bool {
    let check_cmd = if cfg!(windows) { "where" } else { "which" };
    Command::new(check_cmd).arg(cmd).output().map(|o| o.status.success()).unwrap_or(false)
}

fn download_file(url: &str, dest: &Path) -> Result<(), String> {
    let response = ureq::get(url)
        .call()
        .map_err(|e| format!("Network request failed: {}", e))?;

    if response.status() != 200 {
        return Err(format!("Server returned status code {}", response.status()));
    }

    let mut reader = response.into_reader();
    let mut file = File::create(dest).map_err(|e| format!("Failed to create destination file: {}", e))?;
    
    copy(&mut reader, &mut file).map_err(|e| format!("File download save failed: {}", e))?;
    Ok(())
}
