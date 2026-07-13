use keyring::Entry;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct LicenseStatus {
    pub is_licensed: bool,
    pub is_trial: bool,
    pub license_key: String,
    pub is_premium: bool,
}

pub struct LicenseManager {
    keyring_service: &'static str,
    keyring_key_account: &'static str,
    keyring_trial_account: &'static str,
}

#[derive(Serialize, Deserialize)]
struct GumroadVerifyResponse {
    success: bool,
    message: Option<String>,
}

impl LicenseManager {
    pub fn new() -> Self {
        Self {
            keyring_service: "LocSpoofService",
            keyring_key_account: "license_key",
            keyring_trial_account: "trial_mode",
        }
    }

    /// Read the securely stored license key from Credential Manager (Windows) or Keychain (macOS)
    fn get_secure_item(&self, account: &str) -> Option<String> {
        let entry = Entry::new(self.keyring_service, account).ok()?;
        entry.get_password().ok()
    }

    /// Write the license key/trial state to Credential Manager securely
    fn set_secure_item(&self, account: &str, value: &str) -> Result<(), String> {
        let entry = Entry::new(self.keyring_service, account)
            .map_err(|e| format!("Keyring init error: {}", e))?;
        entry.set_password(value)
            .map_err(|e| format!("Failed to save credential: {}", e))
    }

    /// Delete credentials from Credential Manager
    fn delete_secure_item(&self, account: &str) {
        if let Ok(entry) = Entry::new(self.keyring_service, account) {
            entry.delete_password().ok();
        }
    }

    pub fn get_status(&self) -> LicenseStatus {
        let saved_key = self.get_secure_item(self.keyring_key_account);
        let is_trial = self.get_secure_item(self.keyring_trial_account).unwrap_or_default() == "true";

        let is_licensed = if let Some(ref key) = saved_key {
            Self::validate_checksum(key)
        } else {
            is_trial
        };

        LicenseStatus {
            is_licensed,
            is_trial,
            license_key: saved_key.unwrap_or_default(),
            is_premium: is_licensed,
        }
    }

    pub fn start_trial(&self) -> Result<LicenseStatus, String> {
        self.set_secure_item(self.keyring_trial_account, "true")?;
        self.delete_secure_item(self.keyring_key_account);
        Ok(self.get_status())
    }

    pub fn activate(&self, key: &str) -> Result<LicenseStatus, String> {
        let clean_key = Self::normalize(key);

        // 1. Static checksum check (fail fast)
        if !Self::validate_checksum(&clean_key) {
            return Err("Invalid license key structure. Please check for typos.".to_string());
        }

        // 2. Perform Gumroad API verification in a robust try-catch block
        let url = "https://api.gumroad.com/v2/licenses/verify";

        let api_success = match ureq::post(url).send_form(&[
            ("product_id", "1LGZL4m3EYCNJFIKnJ9pAg=="),
            ("license_key", &clean_key),
        ]) {
            Ok(resp) => {
                if let Ok(json) = resp.into_json::<GumroadVerifyResponse>() {
                    json.success
                } else {
                    // Fall back to offline validation if API response cannot be parsed
                    true
                }
            }
            Err(_) => {
                // If API is down / user is offline, allow offline verification based on checksum!
                true
            }
        };

        if !api_success {
            return Err("License activation rejected by licensing server.".to_string());
        }

        // 3. Store securely in Credential Manager
        self.set_secure_item(self.keyring_key_account, &clean_key)?;
        self.delete_secure_item(self.keyring_trial_account);

        Ok(self.get_status())
    }

    pub fn deactivate(&self) -> LicenseStatus {
        self.delete_secure_item(self.keyring_key_account);
        self.delete_secure_item(self.keyring_trial_account);
        self.get_status()
    }

    // MARK: - Key Validation Code (Mod 97 prime sum checksum)

    const PRIMES: [usize; 16] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53];
    const MODULUS: usize = 97;
    const TARGET: usize = 1;

    fn validate_checksum(key: &str) -> bool {
        let cleaned = Self::normalize(key);
        if cleaned.len() != 16 {
            return false;
        }

        let mut sum = 0;
        for (i, ch) in cleaned.chars().enumerate() {
            if let Some(val) = Self::char_to_value(ch) {
                sum += val * Self::PRIMES[i];
            } else {
                return false;
            }
        }
        sum % Self::MODULUS == Self::TARGET
    }

    fn normalize(key: &str) -> String {
        key.to_uppercase()
            .replace("-", "")
            .replace(" ", "")
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .collect()
    }

    fn char_to_value(c: char) -> Option<usize> {
        if c.is_ascii_digit() {
            c.to_digit(10).map(|d| d as usize)
        } else if c.is_ascii_alphabetic() {
            let offset = c as usize - 'A' as usize;
            Some(offset + 10)
        } else {
            None
        }
    }
}
