import Foundation
import Security

/// Commercial License Key validation and activation system using macOS Keychain for secure storage.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published var isLicensed: Bool = false
    @Published var isTrialMode: Bool = false
    @Published var licenseKey: String = ""
    @Published var validationError: String? = nil
    @Published var showProPaywall: Bool = false
    
    // Paywall controller flag
    var isPremiumUser: Bool {
        return isLicensed && !isTrialMode
    }
    
    private let keychainService = "com.pyrollc.locspoof"
    private let keychainKeyAccount = "license_key"
    private let keychainTrialAccount = "trial_mode"
    
    private init() {
        loadLicenseFromKeychain()
    }
    
    // MARK: - Keychain Core Operations
    
    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
    
    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - License Verification Logic
    
    private func loadLicenseFromKeychain() {
        if let savedKey = readFromKeychain(key: keychainKeyAccount), LicenseManager.validate(savedKey) {
            self.licenseKey = LicenseManager.format(savedKey)
            self.isLicensed = true
            self.isTrialMode = false
        } else if readFromKeychain(key: keychainTrialAccount) == "true" {
            self.isTrialMode = true
            self.isLicensed = true
        }
    }
    
    func startTrial() {
        isTrialMode = true
        isLicensed = true
        saveToKeychain(key: keychainTrialAccount, value: "true")
        deleteFromKeychain(key: keychainKeyAccount)
    }
    
    func activate(with key: String) async -> Bool {
        let clean = LicenseManager.normalize(key)
        
        // Static Checksum validation
        guard LicenseManager.validate(clean) else {
            await MainActor.run {
                self.validationError = "Invalid license key pattern."
            }
            return false
        }
        
        guard let url = URL(string: "https://api.gumroad.com/v2/licenses/verify") else {
            await MainActor.run {
                self.validationError = "Licensing server URL error."
            }
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let encodedKey = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
        let bodyParameters = "product_id=1LGZL4m3EYCNJFIKnJ9pAg%3D%3D&license_key=\(encodedKey)"
        request.httpBody = bodyParameters.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            struct GumroadResponse: Decodable {
                let success: Bool
                let message: String?
            }
            
            let gumroadResp = try JSONDecoder().decode(GumroadResponse.self, from: data)
            
            if gumroadResp.success {
                await MainActor.run {
                    self.licenseKey = LicenseManager.format(clean)
                    self.isLicensed = true
                    self.isTrialMode = false
                    self.validationError = nil
                    
                    saveToKeychain(key: keychainKeyAccount, value: clean)
                    deleteFromKeychain(key: keychainTrialAccount)
                }
                return true
            } else {
                await MainActor.run {
                    self.validationError = gumroadResp.message ?? "Invalid or expired license key."
                }
                return false
            }
        } catch {
            await MainActor.run {
                self.validationError = "Verification error: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    func deactivate() {
        self.licenseKey = ""
        self.isLicensed = false
        self.isTrialMode = false
        self.validationError = nil
        deleteFromKeychain(key: keychainKeyAccount)
        deleteFromKeychain(key: keychainTrialAccount)
    }
    
    // MARK: - Key Validation Code (Mod 97 prime sum checksum)
    
    private static let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53]
    private static let modulus = 97
    private static let target = 1
    
    static func validate(_ key: String) -> Bool {
        let cleaned = normalize(key)
        guard cleaned.count == 16 else { return false }
        
        let values = cleaned.compactMap { charToValue($0) }
        guard values.count == 16 else { return false }
        
        var sum = 0
        for i in 0..<16 {
            sum += values[i] * primes[i]
        }
        return sum % modulus == target
    }
    
    static func format(_ raw: String) -> String {
        let clean = normalize(raw)
        guard clean.count == 16 else { return raw }
        let chars = Array(clean)
        return "\(String(chars[0..<4]))-\(String(chars[4..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))"
    }
    
    private static func normalize(_ key: String) -> String {
        return key.uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }
    
    private static func charToValue(_ char: Character) -> Int? {
        if char >= "0" && char <= "9" {
            return Int(String(char))
        } else if char >= "A" && char <= "Z" {
            return Int(char.asciiValue! - Character("A").asciiValue!) + 10
        }
        return nil
    }
}
