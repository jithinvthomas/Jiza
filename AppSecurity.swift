import Foundation
import Security
import LocalAuthentication
import CommonCrypto
import Combine

struct BrowserPIN: Codable, Equatable {
    let salt: Data
    let digest: Data
    static func valid(_ value: String) -> Bool { value.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) } }
    static func create(_ value: String) throws -> BrowserPIN {
        guard valid(value) else { throw LockError.message("Use exactly six digits.") }
        var salt = Data(count: 32)
        let result = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw LockError.message("Could not create a secure PIN. Try again.") }
        return try BrowserPIN(salt: salt, digest: derive(value, salt: salt))
    }
    func matches(_ value: String) throws -> Bool {
        guard Self.valid(value), salt.count == 32, digest.count == 32 else { return false }
        let candidate = try Self.derive(value, salt: salt)
        return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(_ value: String, salt: Data) throws -> Data {
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { outputBytes in
            salt.withUnsafeBytes { saltBytes in
                value.withCString { password in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, value.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000,
                        outputBytes.bindMemory(to: UInt8.self).baseAddress!, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw LockError.message("Could not verify the PIN.") }
        return output
    }
}
struct LockRecord: Codable {
    var appLock = false
    var pin: BrowserPIN?
    var failures = 0
    var retryAfter: Date?
}
enum LockError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
protocol LockStorage {
    func read() throws -> LockRecord
    func write(_ record: LockRecord) throws
}
struct KeychainLockStorage: LockStorage {
    var service = "app.jiza.locks.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "local-locks"]
    }
    func read() throws -> LockRecord {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return LockRecord() }
        guard status == errSecSuccess, let data = result as? Data else { throw LockError.message("Unlock your iPhone, then retry reading the lock settings.") }
        return try JSONDecoder().decode(LockRecord.self, from: data)
    }
    func write(_ record: LockRecord) throws {
        let data = try JSONEncoder().encode(record)
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LockError.message("Could not save lock settings securely. No change was applied.") }
    }
}

@MainActor
final class AppSecurity: ObservableObject {
    @Published private(set) var record = LockRecord()
    @Published private(set) var appUnlocked = false
    @Published private(set) var browserUnlocked = false
    @Published private(set) var busy = false
    @Published private(set) var storageUnavailable = false
    @Published var obscured = false
    @Published var browserVisible = false
    @Published var error: String?
    var returnHome: (() -> Void)?
    private let storage: LockStorage
    private let authenticate: (String) async throws -> Bool
    private let now: () -> Date
    private var generation = UUID()
    var appLockEnabled: Bool { record.appLock }
    var browserLockEnabled: Bool { record.pin != nil }
    var needsAppUnlock: Bool { storageUnavailable || (record.appLock && !appUnlocked) }
    var needsBrowserUnlock: Bool { browserVisible && browserLockEnabled && !browserUnlocked }
    var needsShield: Bool { needsAppUnlock || needsBrowserUnlock || (obscured && (appLockEnabled || browserLockEnabled)) }

    init(storage: LockStorage = KeychainLockStorage(), now: @escaping () -> Date = Date.init,
         authenticate: @escaping (String) async throws -> Bool = { reason in try await AppSecurity.authenticateOwner(reason) }) {
        self.storage = storage; self.now = now; self.authenticate = authenticate
        reload()
    }
    static func authenticateOwner(_ reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw LockError.message("Set an iPhone passcode in Settings before enabling this lock.")
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func reload() {
        do { record = try storage.read(); storageUnavailable = false; error = nil }
        catch { storageUnavailable = true; self.error = error.localizedDescription }
    }
    func lock() {
        generation = UUID(); appUnlocked = false; browserUnlocked = false
    }
    func leaveBrowser() { browserVisible = false; browserUnlocked = false; error = nil }
    func unlockApp() async {
        guard !busy, !storageUnavailable else { return }
        busy = true; error = nil; let request = generation
        defer { busy = false }
        do { if try await authenticate("Unlock Jiza"), request == generation { appUnlocked = true } }
        catch { self.error = "Authentication was cancelled or unsuccessful. Try again." }
    }
    func setAppLock(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; let request = generation
        defer { busy = false }
        do {
            guard try await authenticate(enabled ? "Enable Jiza app lock" : "Disable Jiza app lock"), request == generation else { return }
            var updated = record; updated.appLock = enabled
            try storage.write(updated); record = updated; appUnlocked = true
        } catch { self.error = error.localizedDescription }
    }
    func setPIN(_ pin: String, confirmation: String) async -> Bool {
        guard !busy, BrowserPIN.valid(pin), pin == confirmation else { error = "Enter the same six-digit PIN twice."; return false }
        busy = true; error = nil; let request = generation
        defer { busy = false }
        do {
            guard try await authenticate("Set or change Jiza Browser PIN"), request == generation else { return false }
            let verifier = try await Task.detached(priority: .userInitiated) { try BrowserPIN.create(pin) }.value
            guard request == generation else { return false }
            var updated = record; updated.pin = verifier; updated.failures = 0; updated.retryAfter = nil
            try storage.write(updated); record = updated; browserUnlocked = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func unlockBrowser(_ pin: String) async {
        guard !busy, let verifier = record.pin else { return }
        if let retry = record.retryAfter, retry > now() { error = "Too many attempts. Try again in \(max(1, Int(ceil(retry.timeIntervalSince(now()))))) seconds."; return }
        busy = true; error = nil; let request = generation
        defer { busy = false }
        do {
            let success = try await Task.detached(priority: .userInitiated) { try verifier.matches(pin) }.value
            guard request == generation else { return }
            var updated = record
            if success { updated.failures = 0; updated.retryAfter = nil }
            else {
                updated.failures += 1
                if updated.failures >= 5 { updated.retryAfter = now().addingTimeInterval(min(300, 30 * pow(2, Double(min(updated.failures - 5, 4))))) }
            }
            try storage.write(updated); record = updated
            if success { browserUnlocked = true } else { error = "Incorrect PIN. Please try again." }
        } catch { self.error = error.localizedDescription }
    }
    /// Device-owner authentication is the explicit recovery path, not a PIN bypass.
    func removePIN() async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil; let request = generation
        defer { busy = false }
        do {
            guard try await authenticate("Remove or reset the Jiza Browser PIN"), request == generation else { return false }
            var updated = record; updated.pin = nil; updated.failures = 0; updated.retryAfter = nil
            try storage.write(updated); record = updated; browserUnlocked = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
