import Cocoa
import CryptoKit
import EventKit
import Security
import ServiceManagement
import UserNotifications
import WebKit

// MARK: - Configuration
private let kTaskFilePathDefaultsKey = "stash.taskFilePath"
private let kOnboardingCompletedDefaultsKey = "stash.onboarding.completed"
private let kDefaultTaskFileName = "my_tasks.txt"
private let kDefaultTaskDirectory = "/Users/robsonferreira/Documents"
private let kDefaultFilePath = "\(kDefaultTaskDirectory)/\(kDefaultTaskFileName)"
private var taskFilePath: String {
    UserDefaults.standard.string(forKey: kTaskFilePathDefaultsKey) ?? kDefaultFilePath
}
private let kReminderListName = "Stash"
private let kAIProviderDefaultsKey = "stash.ai.provider"
private let kLanguageDefaultsKey = "stash.language"
private let kOpenAtLoginDefaultsKey = "stash.openAtLogin"
private let kSubscriptionPlanDefaultsKey = "stash.subscription.plan"
private let kLicenseEmailDefaultsKey = "stash.license.email"
private let kGeminiModelDefault = "gemini-3-flash-preview"
private let kGeminiModelDefaultsKey = "stash.ai.google.model"
private let kOpenAIModelDefault = "gpt-5.3"
private let kOpenAIModelDefaultsKey = "stash.ai.openai.model"
private let kAnthropicModelDefault = "claude-opus-4-1"
private let kAnthropicModelDefaultsKey = "stash.ai.anthropic.model"
private let kGoogleAPIKeyAccount = "google_api_key"
private let kOpenAIAPIKeyAccount = "openai_api_key"
private let kAnthropicAPIKeyAccount = "anthropic_api_key"
private let kLicenseKeyAccount = "stash_license_key"
private let kLicenseEntitlementAccount = "stash_license_entitlement"
private let kLicenseDeviceIDAccount = "stash_license_device_id"
private let kLicenseServiceBaseURL = "https://stash-licensing-prod.robsonferr.workers.dev"
private let kStashProPageURL = "https://stash.simplificandoproduto.com.br/pro/"
private let kEntitlementAudience = "stash-macos-app"
private let kEntitlementIssuer = "stash-licensing"
private let kEntitlementRefreshLeadTime: TimeInterval = 60 * 60 * 12
private let kEntitlementRefreshThrottle: TimeInterval = 60 * 5
private let kEntitlementPublicKeyPEM = """
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAekIDFcj1TBdSJ7Zwkov0pJEH8Mx87tmIaH3oS1t4ZbU=
-----END PUBLIC KEY-----
"""
private struct TaskIcon {
    let symbol: String
    let tooltipKey: String
    let placeholderKey: String
    let descriptionKey: String
}

private let kIcons: [TaskIcon] = [
    TaskIcon(symbol: "📥", tooltipKey: "icon.task.tooltip", placeholderKey: "icon.task.placeholder", descriptionKey: "icon.task.description"),
    TaskIcon(symbol: "❓", tooltipKey: "icon.question.tooltip", placeholderKey: "icon.question.placeholder", descriptionKey: "icon.question.description"),
    TaskIcon(symbol: "🎯", tooltipKey: "icon.goal.tooltip", placeholderKey: "icon.goal.placeholder", descriptionKey: "icon.goal.description"),
    TaskIcon(symbol: "🔔", tooltipKey: "icon.reminder.tooltip", placeholderKey: "icon.reminder.placeholder", descriptionKey: "icon.reminder.description"),
]
// Hotkey: Cmd+Shift+Space  (keyCode 49)
private let kHotkeyMask: NSEvent.ModifierFlags = [.command, .shift]
private let kHotkeyCode: UInt16 = 49

// Rewind the Day — notification keys
private let kRewindEnabledKey          = "stash.rewind.enabled"
private let kRewindHourKey             = "stash.rewind.hour"
private let kRewindMinuteKey           = "stash.rewind.minute"
private let kRewindSnoozeCountKey      = "stash.rewind.snoozeCount"
private let kRewindSnoozeDateKey       = "stash.rewind.snoozeDate"
private let kRewindReviewedDateKey     = "stash.rewind.reviewedDate"
private let kRewindNotificationID      = "stash.rewind.daily"
private let kRewindSnoozeNotificationID = "stash.rewind.snooze"
private let kRewindCategoryWithSnooze  = "STASH_REWIND"
private let kRewindCategoryNoSnooze    = "STASH_REWIND_NOSNOOZE"
private let kRewindReviewedEmoji       = "🌅"
private let kRewindDefaultHour         = 17
private let kRewindDefaultMinute       = 30

private extension Notification.Name {
    static let stashLanguageDidChange = Notification.Name("stash.languageDidChange")
}

private enum AppLanguage: String, CaseIterable {
    case system
    case enUS = "en-US"
    case ptBR = "pt-BR"

    var localizationCode: String? {
        switch self {
        case .system: return nil
        case .enUS: return "en-US"
        case .ptBR: return "pt-BR"
        }
    }

    var displayName: String {
        switch self {
        case .system: return L("prefs.language.system")
        case .enUS: return L("prefs.language.enUS")
        case .ptBR: return L("prefs.language.ptBR")
        }
    }

    static func current() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: kLanguageDefaultsKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    static func activeBCP47() -> String {
        if let code = current().localizationCode {
            return code
        }

        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en-US"
        return preferred.lowercased().hasPrefix("pt") ? "pt-BR" : "en-US"
    }
}

private enum SubscriptionPlan: String, CaseIterable {
    case free
    case pro
    case premium

    var displayName: String {
        switch self {
        case .free: return L("prefs.plan.free")
        case .pro: return L("prefs.plan.pro")
        case .premium: return L("prefs.plan.premium")
        }
    }

    var allowsDashboard: Bool {
        self != .free
    }

    static func current() -> SubscriptionPlan {
        LicenseManager.currentPlan()
    }
}

private enum Localizer {
    static func localized(_ key: String) -> String {
        let mainValue = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        guard let code = AppLanguage.current().localizationCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return mainValue
        }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? mainValue : value
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: kLanguageDefaultsKey)
        NotificationCenter.default.post(name: .stashLanguageDidChange, object: nil)
    }
}

private func L(_ key: String) -> String {
    Localizer.localized(key)
}

private func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}

private func htmlEscaped(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private func appShortVersion() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.4.1"
}

private func appBuildVersion() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
}

private func appVersionDisplay() -> String {
    "\(appShortVersion()) (\(appBuildVersion()))"
}

private func aboutPanelCredits() -> NSAttributedString {
    let repoURLString = "https://github.com/robsonferr/stash"
    let issueURLString = "https://github.com/robsonferr/stash/issues/new"

    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
    ]
    var linkAttrs = bodyAttrs
    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue

    let credits = NSMutableAttributedString()

    credits.append(NSAttributedString(
        string: "\(L("about.githubRepository")): ",
        attributes: bodyAttrs
    ))
    if let repoURL = URL(string: repoURLString) {
        var attrs = linkAttrs
        attrs[.link] = repoURL
        credits.append(NSAttributedString(string: repoURLString, attributes: attrs))
    } else {
        credits.append(NSAttributedString(string: repoURLString, attributes: bodyAttrs))
    }

    credits.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
    credits.append(NSAttributedString(
        string: "\(L("about.reportIssue")): ",
        attributes: bodyAttrs
    ))
    if let issueURL = URL(string: issueURLString) {
        var attrs = linkAttrs
        attrs[.link] = issueURL
        credits.append(NSAttributedString(string: issueURLString, attributes: attrs))
    } else {
        credits.append(NSAttributedString(string: issueURLString, attributes: bodyAttrs))
    }

    return credits
}

private enum TaskFileSetupError: Error {
    case emptyDirectory
    case missingDirectory
    case notDirectory
    case cannotCreateFile
    case notWritable
}

private func currentTaskDirectoryPath() -> String {
    let saved = UserDefaults.standard.string(forKey: kTaskFilePathDefaultsKey) ?? kDefaultFilePath
    let url = URL(fileURLWithPath: saved)
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return url.path
    }
    return url.deletingLastPathComponent().path
}

private func validatedTaskFilePath(forDirectory rawDirectory: String) -> Result<String, TaskFileSetupError> {
    let directory = rawDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !directory.isEmpty else { return .failure(.emptyDirectory) }

    let dirURL = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir) else {
        return .failure(.missingDirectory)
    }
    guard isDir.boolValue else { return .failure(.notDirectory) }

    let fileURL = dirURL.appendingPathComponent(kDefaultTaskFileName)
    if !FileManager.default.fileExists(atPath: fileURL.path) {
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            return .failure(.cannotCreateFile)
        }
    }
    guard FileManager.default.isWritableFile(atPath: fileURL.path) else {
        return .failure(.notWritable)
    }
    return .success(fileURL.path)
}

private func taskPathErrorMessage(_ error: TaskFileSetupError) -> String {
    switch error {
    case .emptyDirectory:
        return L("taskPath.error.empty")
    case .missingDirectory:
        return L("taskPath.error.missingDirectory")
    case .notDirectory:
        return L("taskPath.error.notDirectory")
    case .cannotCreateFile:
        return L("taskPath.error.cannotCreate")
    case .notWritable:
        return L("taskPath.error.notWritable")
    }
}

private func presentTaskPathErrorAlert(window: NSWindow?, error: TaskFileSetupError) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L("taskPath.error.title")
    alert.informativeText = taskPathErrorMessage(error)
    if let window {
        alert.beginSheetModal(for: window)
    } else {
        alert.runModal()
    }
}

private func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

private func promptAccessibilityTrustDialog() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

private func hasLegacyConfiguration() -> Bool {
    let defaults = UserDefaults.standard
    let keys = [
        kTaskFilePathDefaultsKey,
        kLanguageDefaultsKey,
        kAIProviderDefaultsKey,
        kOpenAtLoginDefaultsKey,
        kRewindEnabledKey,
        kRewindHourKey,
        kRewindMinuteKey,
        kRewindReviewedDateKey,
    ]
    if keys.contains(where: { defaults.object(forKey: $0) != nil }) {
        return true
    }

    let defaultURL = URL(fileURLWithPath: kDefaultFilePath)
    if FileManager.default.fileExists(atPath: defaultURL.path) {
        return true
    }
    return false
}

private func shouldPresentOnboardingOnLaunch() -> Bool {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: kOnboardingCompletedDefaultsKey) {
        return false
    }
    if hasLegacyConfiguration() {
        defaults.set(true, forKey: kOnboardingCompletedDefaultsKey)
        return false
    }
    return true
}

// MARK: - AI + Secrets
private enum KeychainStore {
    static let service = "com.robsonferreira.stash"

    static func read(account: String) -> String? {
        guard let data = readData(account: account),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func readData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func upsert(account: String, value: String) {
        upsertData(account: account, data: Data(value.utf8))
    }

    static func upsertData(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct SignedEntitlement: Codable {
    let payload: EntitlementPayload
    let signature: String
}

private struct EntitlementPayload: Codable {
    let iss: String?
    let aud: String?
    let license_id: String
    let plan: String
    let status: String
    let customer_email: String?
    let device_id_hash: String?
    let issued_at: String
    let expires_at: String
    let grace_until: String
}

private struct ActivateLicenseResponse: Codable {
    let license_id: String
    let plan: String
    let status: String
    let entitlement: SignedEntitlement
}

private struct RefreshLicenseResponse: Codable {
    let plan: String
    let status: String
    let entitlement: SignedEntitlement
}

private struct LicenseServiceErrorEnvelope: Decodable {
    let error: LicenseServiceErrorPayload
}

private struct LicenseServiceErrorPayload: Decodable {
    let code: String
    let message: String
}

private enum LicenseServiceError: Error {
    case invalidEmail
    case missingCredentials
    case invalidConfiguration
    case invalidEntitlement
    case invalidResponse
    case unsupportedPlatform
    case api(code: String, message: String)
    case transport(String)
}

private enum LicenseLifecycleStatus: String {
    case active
    case gracePeriod = "grace_period"
    case pastDue = "past_due"
    case canceled
    case revoked

    init(rawStatus: String) {
        switch rawStatus.lowercased() {
        case "active": self = .active
        case "grace_period": self = .gracePeriod
        case "past_due": self = .pastDue
        case "canceled": self = .canceled
        case "revoked": self = .revoked
        default: self = .revoked
        }
    }

    var allowsDashboardAccess: Bool {
        switch self {
        case .active, .gracePeriod, .pastDue:
            return true
        case .canceled, .revoked:
            return false
        }
    }
}

private enum LicenseManager {
    private static let entitlementDERPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
    private static var entitlementRefreshInFlight = false
    private static var lastEntitlementRefreshAttemptAt: Date?

    static func currentPlan() -> SubscriptionPlan {
        guard let entitlement = currentEntitlement() else { return .free }
        let status = LicenseLifecycleStatus(rawStatus: entitlement.status)
        guard status.allowsDashboardAccess else { return .free }
        return SubscriptionPlan(rawValue: entitlement.plan.lowercased()) ?? .free
    }

    static func currentEntitlement() -> EntitlementPayload? {
        guard #available(macOS 10.15, *) else { return nil }
        guard let data = KeychainStore.readData(account: kLicenseEntitlementAccount),
              let entitlement = try? JSONDecoder().decode(SignedEntitlement.self, from: data),
              verify(entitlement: entitlement) else {
            return nil
        }
        return entitlement.payload
    }

    static func licenseEmail() -> String {
        UserDefaults.standard.string(forKey: kLicenseEmailDefaultsKey) ?? ""
    }

    static func savedLicenseKey() -> String {
        KeychainStore.read(account: kLicenseKeyAccount) ?? ""
    }

    static func deviceID() -> String {
        if let existing = KeychainStore.read(account: kLicenseDeviceIDAccount), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        KeychainStore.upsert(account: kLicenseDeviceIDAccount, value: generated)
        return generated
    }

    static func statusSummary() -> String {
        guard let entitlement = currentEntitlement() else {
            if !savedLicenseKey().isEmpty {
                return L("prefs.license.status.saved")
            }
            return L("prefs.license.status.none")
        }

        let status = LicenseLifecycleStatus(rawStatus: entitlement.status)
        let expiresLabel = formatDate(entitlement.expires_at) ?? entitlement.expires_at
        switch status {
        case .active:
            return LF("prefs.license.status.active", displayPlanName(entitlement.plan), expiresLabel)
        case .gracePeriod, .pastDue:
            let graceLabel = formatDate(entitlement.grace_until) ?? entitlement.grace_until
            return LF("prefs.license.status.grace", displayPlanName(entitlement.plan), graceLabel)
        case .canceled, .revoked:
            return LF("prefs.license.status.inactive", displayPlanName(entitlement.plan))
        }
    }

    static func openUpgradePage() {
        guard let url = URL(string: kStashProPageURL) else { return }
        NSWorkspace.shared.open(url)
    }

    static func refreshEntitlementIfNeeded() {
        guard let licenseKey = storedLicenseKey() else {
            return
        }

        let now = Date()
        guard !entitlementRefreshInFlight else {
            return
        }

        if let lastAttemptAt = lastEntitlementRefreshAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < kEntitlementRefreshThrottle {
            return
        }

        if let entitlement = currentEntitlement(),
           let expiry = parseISO8601(entitlement.expires_at),
           now.addingTimeInterval(kEntitlementRefreshLeadTime) < expiry {
            return
        }

        entitlementRefreshInFlight = true
        lastEntitlementRefreshAttemptAt = now
        refresh(email: licenseEmail(), licenseKey: licenseKey) { result in
            entitlementRefreshInFlight = false
            if case .failure(let error) = result {
                print("Stash license refresh failed: \(error)")
            }
        }
    }

    static func activate(email: String, licenseKey: String, completion: @escaping (Result<EntitlementPayload, LicenseServiceError>) -> Void) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            completion(.failure(.invalidEmail))
            return
        }
        guard !trimmedKey.isEmpty else {
            completion(.failure(.missingCredentials))
            return
        }

        let body: [String: Any] = [
            "email": trimmedEmail,
            "license_key": trimmedKey,
            "device_id": deviceID(),
            "device_label": Host.current().localizedName ?? "Mac"
        ]

        performRequest(path: "/licenses/activate", body: body) { (result: Result<ActivateLicenseResponse, LicenseServiceError>) in
            switch result {
            case .success(let response):
                do {
                    try storeValidatedEntitlement(response.entitlement)
                    UserDefaults.standard.set(trimmedEmail, forKey: kLicenseEmailDefaultsKey)
                    KeychainStore.upsert(account: kLicenseKeyAccount, value: trimmedKey)
                    completion(.success(response.entitlement.payload))
                } catch let error as LicenseServiceError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.invalidEntitlement))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func refresh(email: String? = nil, licenseKey: String? = nil, completion: @escaping (Result<EntitlementPayload, LicenseServiceError>) -> Void) {
        let resolvedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? licenseEmail()
        let resolvedKey = licenseKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? storedLicenseKey()
        guard let resolvedKey, !resolvedKey.isEmpty else {
            completion(.failure(.missingCredentials))
            return
        }

        var body: [String: Any] = [
            "license_key": resolvedKey,
            "device_id": deviceID()
        ]
        if !resolvedEmail.isEmpty {
            body["email"] = resolvedEmail
        }

        performRequest(path: "/licenses/refresh", body: body) { (result: Result<RefreshLicenseResponse, LicenseServiceError>) in
            switch result {
            case .success(let response):
                do {
                    try storeValidatedEntitlement(response.entitlement)
                    completion(.success(response.entitlement.payload))
                } catch let error as LicenseServiceError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.invalidEntitlement))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func storedLicenseKey() -> String? {
        let value = KeychainStore.read(account: kLicenseKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func storeValidatedEntitlement(_ entitlement: SignedEntitlement) throws {
        guard #available(macOS 10.15, *) else {
            throw LicenseServiceError.unsupportedPlatform
        }
        guard verify(entitlement: entitlement) else {
            throw LicenseServiceError.invalidEntitlement
        }
        let data = try JSONEncoder().encode(entitlement)
        KeychainStore.upsertData(account: kLicenseEntitlementAccount, data: data)
    }

    private static func verify(entitlement: SignedEntitlement) -> Bool {
        guard #available(macOS 10.15, *) else {
            return false
        }
        guard let payloadData = try? JSONEncoder().encode(entitlement.payload),
              let signatureData = Data(base64Encoded: entitlement.signature),
              let publicKey = loadPublicKey() else {
            return false
        }

        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            return false
        }

        guard entitlement.payload.aud == kEntitlementAudience,
              entitlement.payload.iss == kEntitlementIssuer,
              let graceUntil = parseISO8601(entitlement.payload.grace_until),
              Date() <= graceUntil else {
            return false
        }

        return true
    }

    @available(macOS 10.15, *)
    private static func loadPublicKey() -> Curve25519.Signing.PublicKey? {
        let base64 = kEntitlementPublicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let decoded = Data(base64Encoded: base64) else {
            return nil
        }

        let rawKey: Data
        if decoded.count == 32 {
            rawKey = decoded
        } else if decoded.starts(with: entitlementDERPrefix), decoded.count == entitlementDERPrefix.count + 32 {
            rawKey = decoded.suffix(32)
        } else {
            return nil
        }

        return try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func formatDate(_ value: String) -> String? {
        guard let date = parseISO8601(value) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func displayPlanName(_ rawValue: String) -> String {
        let plan = SubscriptionPlan(rawValue: rawValue.lowercased()) ?? .free
        return plan.displayName
    }

    private static func performRequest<Response: Decodable>(
        path: String,
        body: [String: Any],
        completion: @escaping (Result<Response, LicenseServiceError>) -> Void
    ) {
        guard let url = URL(string: kLicenseServiceBaseURL + path),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.invalidConfiguration))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<Response, LicenseServiceError>) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            if let error {
                finish(.failure(.transport(error.localizedDescription)))
                return
            }

            guard let http = response as? HTTPURLResponse, let data else {
                finish(.failure(.invalidResponse))
                return
            }

            if (200..<300).contains(http.statusCode) {
                guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
                    finish(.failure(.invalidResponse))
                    return
                }
                finish(.success(parsed))
                return
            }

            if let apiError = try? JSONDecoder().decode(LicenseServiceErrorEnvelope.self, from: data) {
                finish(.failure(.api(code: apiError.error.code, message: apiError.error.message)))
                return
            }

            finish(.failure(.invalidResponse))
        }.resume()
    }
}

private enum AIProvider: String, CaseIterable {
    case google
    case openai
    case anthropic

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var modelDefaultsKey: String {
        switch self {
        case .google: return kGeminiModelDefaultsKey
        case .openai: return kOpenAIModelDefaultsKey
        case .anthropic: return kAnthropicModelDefaultsKey
        }
    }

    var modelDefault: String {
        switch self {
        case .google: return kGeminiModelDefault
        case .openai: return kOpenAIModelDefault
        case .anthropic: return kAnthropicModelDefault
        }
    }

    var keychainAccount: String {
        switch self {
        case .google: return kGoogleAPIKeyAccount
        case .openai: return kOpenAIAPIKeyAccount
        case .anthropic: return kAnthropicAPIKeyAccount
        }
    }

    var envVarName: String {
        switch self {
        case .google: return "GOOGLE_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        }
    }
}

private struct ParsedReminder {
    let title: String
    let dueDate: Date?
}

private enum ReminderAIParser {
    static func parse(_ input: String) -> ParsedReminder? {
        let provider = selectedProvider()
        guard let key = resolvedAPIKey(provider: provider), !key.isEmpty else { return nil }

        let model = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.modelDefault
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let timezone = TimeZone.current.identifier
        let prompt = """
        Extract reminder intent from user text and return JSON only.

        Rules:
        - Output ONLY valid JSON with keys: title, datetime_iso8601, confidence.
        - title: concise action text without date words.
        - datetime_iso8601: RFC3339 date-time with timezone offset when present, or null if unknown.
        - confidence: number from 0 to 1.

        Context:
        - now: \(nowISO)
        - timezone: \(timezone)
        - language: \(appLanguageTag())

        User text:
        \(input)
        """

        switch provider {
        case .google:
            return parseWithGoogle(prompt: prompt, key: key, model: model, fallbackTitle: input)
        case .openai:
            return parseWithOpenAI(prompt: prompt, key: key, model: model, fallbackTitle: input)
        case .anthropic:
            return parseWithAnthropic(prompt: prompt, key: key, model: model, fallbackTitle: input)
        }
    }

    private static func appLanguageTag() -> String {
        AppLanguage.activeBCP47()
    }

    private static func selectedProvider() -> AIProvider {
        let raw = UserDefaults.standard.string(forKey: kAIProviderDefaultsKey) ?? AIProvider.google.rawValue
        return AIProvider(rawValue: raw) ?? .google
    }

    private static func parseWithGoogle(prompt: String, key: String, model: String, fallbackTitle: String) -> ParsedReminder? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            return nil
        }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json",
            ],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        guard let response = performRequest(request) else { return nil }
        return parseGeminiResponse(response, fallbackTitle: fallbackTitle)
    }

    private static func parseWithOpenAI(prompt: String, key: String, model: String, fallbackTitle: String) -> ParsedReminder? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return nil }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": "You extract reminder title and datetime from user text. Return only strict JSON."],
                ["role": "user", "content": prompt],
            ],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        guard let data = performRequest(request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else { return nil }

        return parseJSONPayload(text, fallbackTitle: fallbackTitle)
    }

    private static func parseWithAnthropic(prompt: String, key: String, model: String, fallbackTitle: String) -> ParsedReminder? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "temperature": 0.1,
            "system": "You extract reminder title and datetime from user text. Return only strict JSON.",
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        guard let data = performRequest(request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]],
              let text = content.compactMap({ $0["text"] as? String }).first else { return nil }

        return parseJSONPayload(text, fallbackTitle: fallbackTitle)
    }

    private static func performRequest(_ request: URLRequest) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var payload: Data?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            payload = data
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 12)
        return payload
    }

    private static func parseJSONPayload(_ text: String, fallbackTitle: String) -> ParsedReminder? {
        let normalized = stripCodeFence(text)
        guard let jsonData = normalized.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let title = (parsed["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenTitle = (title?.isEmpty == false) ? title! : fallbackTitle

        var dueDate: Date?
        if let dateText = parsed["datetime_iso8601"] as? String,
           !dateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dueDate = parseISODate(dateText)
        }

        return ParsedReminder(title: chosenTitle, dueDate: dueDate)
    }

    private static func resolvedAPIKey(provider: AIProvider) -> String? {
        if let fromKeychain = KeychainStore.read(account: provider.keychainAccount), !fromKeychain.isEmpty {
            return fromKeychain
        }
        if let fromEnv = ProcessInfo.processInfo.environment[provider.envVarName], !fromEnv.isEmpty {
            return fromEnv
        }
        return nil
    }

    private static func parseGeminiResponse(_ data: Data, fallbackTitle: String) -> ParsedReminder? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first else {
            return nil
        }

        return parseJSONPayload(text, fallbackTitle: fallbackTitle)
    }

    private static func stripCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let lines = trimmed.components(separatedBy: "\n")
        let filtered = lines.filter { !$0.hasPrefix("```") }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let dt = fmt.date(from: value) { return dt }

        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: value)
    }
}

// MARK: - Review Models

private struct StashEntry {
    let dayDate: Date
    let lineIndex: Int
    let icon: String
    let text: String
    var isDone: Bool
    var doneDate: Date?
    var reminderDate: Date?
    var carriedFromDate: Date?
    var carryoverToDate: Date?
}

private struct DayBlock {
    let date: Date
    var entries: [StashEntry]
}

private enum ReviewPeriod {
    case day(Date)
    case week(start: Date, end: Date)
}

private enum ReviewCarryoverError: Error {
    case unreadableFile
    case invalidSourceEntry
    case alreadyCarriedForward
    case writeFailed
}

private func carryoverErrorMessage(_ error: ReviewCarryoverError) -> String {
    switch error {
    case .unreadableFile:
        return L("review.carryover.error.read")
    case .invalidSourceEntry:
        return L("review.carryover.error.invalidSource")
    case .alreadyCarriedForward:
        return L("review.carryover.error.duplicate")
    case .writeFailed:
        return L("review.carryover.error.write")
    }
}

private enum DashboardPeriodPreset: String, CaseIterable {
    case last7Days
    case last14Days
    case last30Days
    case all
    case custom

    var displayName: String {
        switch self {
        case .last7Days: return L("dashboard.period.last7")
        case .last14Days: return L("dashboard.period.last14")
        case .last30Days: return L("dashboard.period.last30")
        case .all: return L("dashboard.period.all")
        case .custom: return L("dashboard.period.custom")
        }
    }
}

private enum DashboardCategory: String, CaseIterable {
    case task
    case reminder
    case question
    case goal

    var icon: String {
        switch self {
        case .task: return "📥"
        case .reminder: return "🔔"
        case .question: return "❓"
        case .goal: return "🎯"
        }
    }

    var colorHex: String {
        switch self {
        case .task: return "#6c5ce7"
        case .reminder: return "#74b9ff"
        case .question: return "#fdcb6e"
        case .goal: return "#fd79a8"
        }
    }

    var label: String {
        switch self {
        case .task: return L("dashboard.category.task")
        case .reminder: return L("dashboard.category.reminder")
        case .question: return L("dashboard.category.question")
        case .goal: return L("dashboard.category.goal")
        }
    }

    static func from(icon: String) -> DashboardCategory? {
        switch icon {
        case "📥", "✅": return .task
        case "🔔": return .reminder
        case "❓": return .question
        case "🎯": return .goal
        default: return nil
        }
    }
}

private enum DashboardBadgeStyle: String {
    case green
    case orange
    case red
    case blue

    var cssClass: String {
        "badge-\(rawValue)"
    }
}

private struct DashboardEntryRecord {
    let icon: String
    let text: String
    let category: DashboardCategory
    let createdAt: Date
    let isDone: Bool
    let doneDate: Date?
    let reminderDate: Date?
}

private struct DashboardMetricCard {
    let label: String
    let value: String
    let detail: String
    let accentHex: String
}

private struct DashboardBarPoint {
    let label: String
    let primary: Int
    let secondary: Int?
}

private struct DashboardDonutSegment {
    let icon: String
    let label: String
    let value: Int
    let colorHex: String
}

private struct DashboardListItem {
    let icon: String
    let text: String
    let metaText: String?
    let badgeText: String?
    let badgeStyle: DashboardBadgeStyle?
}

private struct DashboardSummary {
    let title: String
    let subtitle: String
    let emptyStateMessage: String?
    let upgradeMessage: String?
    let metricCards: [DashboardMetricCard]
    let weeklyPoints: [DashboardBarPoint]
    let dailyPoints: [DashboardBarPoint]
    let categorySegments: [DashboardDonutSegment]
    let backlogItems: [DashboardListItem]
    let reminderItems: [DashboardListItem]
    let showsCategoryBreakdown: Bool
    let showsDeepInsights: Bool
    let weeklyTitle: String
    let categoryTitle: String
    let dailyTitle: String
    let backlogTitle: String
    let remindersTitle: String
    let weeklyPrimaryLegend: String
    let weeklySecondaryLegend: String
    let chartEmptyMessage: String
    let categoryEmptyMessage: String
    let backlogEmptyMessage: String
    let remindersEmptyMessage: String
}

private enum DashboardAccessLevel {
    case pro
    case premium

    static func current() -> DashboardAccessLevel {
        SubscriptionPlan.current() == .premium ? .premium : .pro
    }

    var allowedPresets: [DashboardPeriodPreset] {
        switch self {
        case .pro:
            return [.last7Days, .last14Days, .last30Days]
        case .premium:
            return DashboardPeriodPreset.allCases
        }
    }

    var showsCategoryBreakdown: Bool {
        self == .premium
    }

    var showsDeepInsights: Bool {
        self == .premium
    }

    var upgradeMessage: String? {
        switch self {
        case .pro:
            return L("dashboard.pro.upgradeHint")
        case .premium:
            return nil
        }
    }
}

private enum DashboardDataBuilder {
    private static let calendar = Calendar.current

    static func build(preset: DashboardPeriodPreset, customStart: Date, customEnd: Date) -> DashboardSummary {
        let accessLevel = DashboardAccessLevel.current()
        let allEntries = StashFileParser.parse(from: taskFilePath)
            .flatMap(\.entries)
            .compactMap(record(from:))
            .sorted { $0.createdAt < $1.createdAt }

        let range = selectedRange(for: preset, customStart: customStart, customEnd: customEnd)
        let filteredEntries = allEntries.filter { entry in
            let day = calendar.startOfDay(for: entry.createdAt)
            if let start = range.start, day < start { return false }
            if let end = range.end, day > end { return false }
            return true
        }

        let displayRange = rangeForDisplay(filteredEntries: filteredEntries, allEntries: allEntries, explicitRange: range)
        let subtitle = subtitleText(for: preset, displayRange: displayRange, hasEntries: !filteredEntries.isEmpty)

        let total = filteredEntries.count
        let completed = filteredEntries.filter(\.isDone).count
        let open = max(0, total - completed)
        let completionRate = total > 0 ? Int(round((Double(completed) / Double(total)) * 100.0)) : 0

        let resolutionValues = filteredEntries.compactMap { entry -> Double? in
            guard entry.isDone, let doneDate = entry.doneDate else { return nil }
            let start = calendar.startOfDay(for: entry.createdAt)
            let end = calendar.startOfDay(for: doneDate)
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            return Double(max(0, days))
        }
        let averageResolution = resolutionValues.isEmpty ? nil : resolutionValues.reduce(0, +) / Double(resolutionValues.count)

        var categoryCounts = Dictionary(uniqueKeysWithValues: DashboardCategory.allCases.map { ($0, 0) })
        filteredEntries.forEach { categoryCounts[$0.category, default: 0] += 1 }
        let activeCategories = categoryCounts.values.filter { $0 > 0 }.count

        let backlogItems = accessLevel.showsDeepInsights ? buildBacklogItems(from: allEntries) : []
        let reminderItems = accessLevel.showsDeepInsights ? buildUpcomingReminderItems(from: allEntries) : []

        let metricCards = [
            DashboardMetricCard(
                label: L("dashboard.metric.total"),
                value: "\(total)",
                detail: metricDetailRange(displayRange),
                accentHex: "#6c5ce7"
            ),
            DashboardMetricCard(
                label: L("dashboard.metric.completed"),
                value: "\(completed)",
                detail: LF("dashboard.detail.completionRate", "\(completionRate)%"),
                accentHex: "#00b894"
            ),
            DashboardMetricCard(
                label: L("dashboard.metric.open"),
                value: "\(open)",
                detail: L("dashboard.detail.awaitingAction"),
                accentHex: "#fdcb6e"
            ),
            DashboardMetricCard(
                label: L("dashboard.metric.avgResolution"),
                value: formattedAverageResolution(averageResolution),
                detail: averageResolution == nil ? L("dashboard.detail.noData") : L("dashboard.detail.daysUnit"),
                accentHex: "#74b9ff"
            ),
            DashboardMetricCard(
                label: L("dashboard.metric.futureReminders"),
                value: "\(reminderItems.count)",
                detail: L("dashboard.detail.scheduledAhead"),
                accentHex: "#fd79a8"
            ),
            DashboardMetricCard(
                label: L("dashboard.metric.activeCategories"),
                value: "\(activeCategories)",
                detail: L("dashboard.detail.ofPossible"),
                accentHex: "#e17055"
            ),
        ]

        let weeklyPoints = buildWeeklyPoints(from: filteredEntries, range: range)
        let dailyPoints = buildDailyPoints(from: filteredEntries)
        let categorySegments = accessLevel.showsCategoryBreakdown ? DashboardCategory.allCases.compactMap { category -> DashboardDonutSegment? in
            let value = categoryCounts[category, default: 0]
            guard value > 0 else { return nil }
            return DashboardDonutSegment(
                icon: category.icon,
                label: category.label,
                value: value,
                colorHex: category.colorHex
            )
        } : []

        return DashboardSummary(
            title: L("dashboard.title"),
            subtitle: subtitle,
            emptyStateMessage: filteredEntries.isEmpty ? L("dashboard.empty.period") : nil,
            upgradeMessage: accessLevel.upgradeMessage,
            metricCards: metricCards,
            weeklyPoints: weeklyPoints,
            dailyPoints: dailyPoints,
            categorySegments: categorySegments,
            backlogItems: backlogItems,
            reminderItems: reminderItems,
            showsCategoryBreakdown: accessLevel.showsCategoryBreakdown,
            showsDeepInsights: accessLevel.showsDeepInsights,
            weeklyTitle: L("dashboard.graph.weekly"),
            categoryTitle: L("dashboard.graph.categories"),
            dailyTitle: L("dashboard.graph.daily"),
            backlogTitle: L("dashboard.table.backlog"),
            remindersTitle: L("dashboard.table.reminders"),
            weeklyPrimaryLegend: L("dashboard.series.captured"),
            weeklySecondaryLegend: L("dashboard.series.completed"),
            chartEmptyMessage: L("dashboard.empty.chart"),
            categoryEmptyMessage: L("dashboard.empty.categories"),
            backlogEmptyMessage: L("dashboard.empty.backlog"),
            remindersEmptyMessage: L("dashboard.empty.reminders")
        )
    }

    private static func record(from entry: StashEntry) -> DashboardEntryRecord? {
        guard let category = DashboardCategory.from(icon: entry.icon) else { return nil }
        return DashboardEntryRecord(
            icon: entry.icon,
            text: entry.text,
            category: category,
            createdAt: entry.dayDate,
            isDone: entry.isDone || entry.icon == "✅",
            doneDate: entry.doneDate,
            reminderDate: entry.reminderDate
        )
    }

    private static func selectedRange(for preset: DashboardPeriodPreset, customStart: Date, customEnd: Date) -> (start: Date?, end: Date?) {
        let today = calendar.startOfDay(for: Date())
        switch preset {
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: today), today)
        case .last14Days:
            return (calendar.date(byAdding: .day, value: -13, to: today), today)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: today), today)
        case .all:
            return (nil, nil)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.startOfDay(for: max(customStart, customEnd))
            return (start, end)
        }
    }

    private static func rangeForDisplay(
        filteredEntries: [DashboardEntryRecord],
        allEntries: [DashboardEntryRecord],
        explicitRange: (start: Date?, end: Date?)
    ) -> (start: Date, end: Date)? {
        if let first = filteredEntries.first?.createdAt, let last = filteredEntries.last?.createdAt {
            return (calendar.startOfDay(for: first), calendar.startOfDay(for: last))
        }
        if let start = explicitRange.start, let end = explicitRange.end {
            return (start, end)
        }
        if let first = allEntries.first?.createdAt, let last = allEntries.last?.createdAt {
            return (calendar.startOfDay(for: first), calendar.startOfDay(for: last))
        }
        return nil
    }

    private static func subtitleText(
        for preset: DashboardPeriodPreset,
        displayRange: (start: Date, end: Date)?,
        hasEntries: Bool
    ) -> String {
        guard let displayRange else {
            return LF("dashboard.subtitle.empty", preset.displayName)
        }
        if !hasEntries {
            return LF("dashboard.subtitle.empty", preset.displayName)
        }
        return LF(
            "dashboard.subtitle.range",
            preset.displayName,
            localizedShortDate(displayRange.start),
            localizedShortDate(displayRange.end)
        )
    }

    private static func metricDetailRange(_ displayRange: (start: Date, end: Date)?) -> String {
        guard let displayRange else { return L("dashboard.detail.noData") }
        return "\(localizedShortDate(displayRange.start)) — \(localizedShortDate(displayRange.end))"
    }

    private static func formattedAverageResolution(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private static func buildWeeklyPoints(
        from entries: [DashboardEntryRecord],
        range: (start: Date?, end: Date?)
    ) -> [DashboardBarPoint] {
        guard !entries.isEmpty else { return [] }
        let firstDate = range.start ?? calendar.startOfDay(for: entries.first!.createdAt)
        let lastDate = range.end ?? calendar.startOfDay(for: entries.last!.createdAt)
        var cursor = startOfWeek(for: firstDate)
        let finalWeek = startOfWeek(for: lastDate)

        var capturedCounts: [Date: Int] = [:]
        var completedCounts: [Date: Int] = [:]

        entries.forEach { entry in
            let createdWeek = startOfWeek(for: entry.createdAt)
            capturedCounts[createdWeek, default: 0] += 1

            guard entry.isDone, let doneDate = entry.doneDate else { return }
            let doneDay = calendar.startOfDay(for: doneDate)
            if let start = range.start, doneDay < start { return }
            if let end = range.end, doneDay > end { return }
            completedCounts[startOfWeek(for: doneDate), default: 0] += 1
        }

        var points: [DashboardBarPoint] = []
        while cursor <= finalWeek {
            points.append(DashboardBarPoint(
                label: compactDateLabel(cursor),
                primary: capturedCounts[cursor, default: 0],
                secondary: completedCounts[cursor, default: 0]
            ))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private static func buildDailyPoints(from entries: [DashboardEntryRecord]) -> [DashboardBarPoint] {
        guard !entries.isEmpty else { return [] }
        var counts: [Date: Int] = [:]
        entries.forEach { entry in
            counts[calendar.startOfDay(for: entry.createdAt), default: 0] += 1
        }
        return counts.keys.sorted().map { date in
            DashboardBarPoint(label: compactDateLabel(date), primary: counts[date, default: 0], secondary: nil)
        }
    }

    private static func buildBacklogItems(from entries: [DashboardEntryRecord]) -> [DashboardListItem] {
        let today = calendar.startOfDay(for: Date())
        return entries
            .filter { !$0.isDone }
            .sorted {
                let lhsAge = ageInDays(from: $0.createdAt, to: today)
                let rhsAge = ageInDays(from: $1.createdAt, to: today)
                return lhsAge > rhsAge
            }
            .map { entry in
                let age = ageInDays(from: entry.createdAt, to: today)
                let style: DashboardBadgeStyle
                switch age {
                case 14...: style = .red
                case 7...: style = .orange
                default: style = .green
                }
                return DashboardListItem(
                    icon: entry.icon,
                    text: entry.text,
                    metaText: localizedShortDate(entry.createdAt),
                    badgeText: LF("dashboard.badge.age", age),
                    badgeStyle: style
                )
            }
    }

    private static func buildUpcomingReminderItems(from entries: [DashboardEntryRecord]) -> [DashboardListItem] {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return entries
            .filter { $0.category == .reminder && !$0.isDone && ($0.reminderDate ?? .distantPast) >= now }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
            .map { entry in
                DashboardListItem(
                    icon: "🔔",
                    text: entry.text,
                    metaText: nil,
                    badgeText: entry.reminderDate.map { formatter.string(from: $0) },
                    badgeStyle: .blue
                )
            }
    }

    private static func localizedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func compactDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("dd/MM")
        return formatter.string(from: date)
    }

    private static func startOfWeek(for date: Date) -> Date {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return calendar.startOfDay(for: interval.start)
        }
        return calendar.startOfDay(for: date)
    }

    private static func ageInDays(from start: Date, to end: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: end).day ?? 0)
    }
}

private enum DashboardHTMLRenderer {
    static func render(summary: DashboardSummary) -> String {
        let metricsHTML = summary.metricCards.map(renderMetricCard).joined()
        let emptyBanner = summary.emptyStateMessage.map {
            """
            <div class="empty-banner">\(
                htmlEscaped($0)
            )</div>
            """
        } ?? ""
        let upgradeBanner = summary.upgradeMessage.map {
            """
            <div class="upsell-banner">\(
                htmlEscaped($0)
            )</div>
            """
        } ?? ""
        let categoryPanel = summary.showsCategoryBreakdown ? """
              <div class="chart-panel">
                <h3>\(htmlEscaped(summary.categoryTitle))</h3>
                \(renderDonutChart(segments: summary.categorySegments, emptyMessage: summary.categoryEmptyMessage))
              </div>
        """ : ""
        let weeklyPanelClass = summary.showsCategoryBreakdown ? "chart-panel" : "chart-panel full-width"
        let deepInsightsSection = summary.showsDeepInsights ? """
            <div class="tables-grid">
              <div class="table-panel">
                <h3>🕐 \(htmlEscaped(summary.backlogTitle))</h3>
                \(renderList(items: summary.backlogItems, emptyMessage: summary.backlogEmptyMessage))
              </div>
              <div class="table-panel">
                <h3>🔔 \(htmlEscaped(summary.remindersTitle))</h3>
                \(renderList(items: summary.reminderItems, emptyMessage: summary.remindersEmptyMessage))
              </div>
            </div>
        """ : ""

        return """
        <!DOCTYPE html>
        <html lang="\(htmlEscaped(AppLanguage.activeBCP47()))">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(htmlEscaped(summary.title))</title>
        <style>
          :root {
            --bg: #0f1117;
            --surface: #1a1d27;
            --surface2: #232736;
            --border: #2e3345;
            --text: #e4e6f0;
            --text-dim: #8b8fa3;
            --accent: #6c5ce7;
            --green: #00b894;
            --orange: #fdcb6e;
            --red: #e17055;
            --blue: #74b9ff;
            --pink: #fd79a8;
          }

          * { box-sizing: border-box; }

          body {
            margin: 0;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", system-ui, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.5;
          }

          .header {
            padding: 28px 40px 22px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
          }

          .header-left {
            display: flex;
            align-items: center;
            gap: 14px;
          }

          .logo {
            font-size: 28px;
          }

          h1 {
            margin: 0;
            font-size: 22px;
            font-weight: 600;
            letter-spacing: -0.3px;
          }

          .subtitle {
            margin-top: 2px;
            color: var(--text-dim);
            font-size: 13px;
          }

          .container {
            max-width: 1280px;
            margin: 0 auto;
            padding: 28px 40px 60px;
          }

          .empty-banner {
            margin-bottom: 16px;
            padding: 14px 16px;
            background: rgba(225, 112, 85, 0.12);
            border: 1px solid rgba(225, 112, 85, 0.3);
            border-radius: 12px;
            color: #ffd8d0;
            font-size: 13px;
          }

          .upsell-banner {
            margin-bottom: 16px;
            padding: 14px 16px;
            background: rgba(108, 92, 231, 0.12);
            border: 1px solid rgba(108, 92, 231, 0.35);
            border-radius: 12px;
            color: #ddd8ff;
            font-size: 13px;
          }

          .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
            margin-bottom: 28px;
          }

          .kpi-card {
            --accent-card: var(--accent);
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 20px;
            position: relative;
            overflow: hidden;
          }

          .kpi-card::before {
            content: "";
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: var(--accent-card);
          }

          .kpi-label {
            font-size: 12px;
            color: var(--text-dim);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
          }

          .kpi-value {
            font-size: 32px;
            font-weight: 700;
            letter-spacing: -1px;
          }

          .kpi-sub {
            font-size: 12px;
            color: var(--text-dim);
            margin-top: 4px;
          }

          .charts-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
            margin-bottom: 28px;
          }

          .full-width {
            grid-column: 1 / -1;
          }

          .chart-panel,
          .table-panel {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 20px;
          }

          .chart-panel h3,
          .table-panel h3 {
            margin: 0 0 16px;
            font-size: 14px;
            font-weight: 600;
          }

          .chart-legend {
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            margin-bottom: 12px;
            color: var(--text-dim);
            font-size: 12px;
          }

          .legend-dot {
            width: 10px;
            height: 10px;
            border-radius: 999px;
            display: inline-block;
          }

          .legend-item {
            display: inline-flex;
            align-items: center;
            gap: 6px;
          }

          .chart-svg {
            width: 100%;
            height: auto;
            display: block;
          }

          .chart-empty {
            height: 260px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--text-dim);
            font-size: 13px;
            border: 1px dashed var(--border);
            border-radius: 10px;
            background: rgba(255, 255, 255, 0.02);
          }

          .donut-layout {
            display: flex;
            align-items: center;
            gap: 24px;
            min-height: 240px;
          }

          .donut-legend {
            display: grid;
            gap: 10px;
            flex: 1;
          }

          .donut-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            color: var(--text-dim);
            font-size: 13px;
          }

          .donut-item strong {
            color: var(--text);
            font-weight: 600;
          }

          .tables-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
          }

          .list-empty {
            padding: 20px 0;
            text-align: center;
            color: var(--text-dim);
            font-size: 13px;
          }

          .task-item {
            display: flex;
            align-items: flex-start;
            gap: 10px;
            padding: 10px 0;
            border-bottom: 1px solid var(--border);
            font-size: 13px;
          }

          .task-item:last-child {
            border-bottom: none;
          }

          .task-emoji {
            font-size: 16px;
            flex-shrink: 0;
            margin-top: 1px;
          }

          .task-body {
            flex: 1;
            min-width: 0;
          }

          .task-text {
            color: var(--text);
          }

          .task-meta {
            color: var(--text-dim);
            font-size: 11px;
            margin-top: 2px;
          }

          .task-date {
            color: var(--text-dim);
            font-size: 11px;
            white-space: nowrap;
            flex-shrink: 0;
          }

          .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 10px;
            font-size: 11px;
            font-weight: 500;
          }

          .badge-red { background: rgba(225, 112, 85, 0.15); color: var(--red); }
          .badge-orange { background: rgba(253, 203, 110, 0.15); color: var(--orange); }
          .badge-green { background: rgba(0, 184, 148, 0.15); color: var(--green); }
          .badge-blue { background: rgba(116, 185, 255, 0.15); color: var(--blue); }

          @media (max-width: 900px) {
            .charts-grid,
            .tables-grid {
              grid-template-columns: 1fr;
            }

            .full-width {
              grid-column: auto;
            }

            .donut-layout {
              flex-direction: column;
              align-items: flex-start;
            }
          }

          @media (max-width: 768px) {
            .container { padding: 20px; }
            .header { padding: 20px; }
          }
        </style>
        </head>
        <body>
          <div class="header">
            <div class="header-left">
              <span class="logo">📦</span>
              <div>
                <h1>\(htmlEscaped(summary.title))</h1>
                <div class="subtitle">\(htmlEscaped(summary.subtitle))</div>
              </div>
            </div>
          </div>
          <div class="container">
            \(emptyBanner)
            \(upgradeBanner)
            <div class="kpi-grid">\(metricsHTML)</div>
            <div class="charts-grid">
              <div class="\(weeklyPanelClass)">
                <h3>\(htmlEscaped(summary.weeklyTitle))</h3>
                <div class="chart-legend">
                  <span class="legend-item"><span class="legend-dot" style="background:#6c5ce7;"></span>\(htmlEscaped(summary.weeklyPrimaryLegend))</span>
                  <span class="legend-item"><span class="legend-dot" style="background:#00b894;"></span>\(htmlEscaped(summary.weeklySecondaryLegend))</span>
                </div>
                \(renderGroupedBarChart(points: summary.weeklyPoints, emptyMessage: summary.chartEmptyMessage))
              </div>
              \(categoryPanel)
              <div class="chart-panel full-width">
                <h3>\(htmlEscaped(summary.dailyTitle))</h3>
                \(renderSingleBarChart(points: summary.dailyPoints, emptyMessage: summary.chartEmptyMessage))
              </div>
            </div>
            \(deepInsightsSection)
          </div>
        </body>
        </html>
        """
    }

    private static func renderMetricCard(_ metric: DashboardMetricCard) -> String {
        """
        <div class="kpi-card" style="--accent-card:\(metric.accentHex);">
          <div class="kpi-label">\(htmlEscaped(metric.label))</div>
          <div class="kpi-value">\(htmlEscaped(metric.value))</div>
          <div class="kpi-sub">\(htmlEscaped(metric.detail))</div>
        </div>
        """
    }

    private static func renderGroupedBarChart(points: [DashboardBarPoint], emptyMessage: String) -> String {
        guard !points.isEmpty else {
            return "<div class=\"chart-empty\">\(htmlEscaped(emptyMessage))</div>"
        }

        let width = 640.0
        let height = 260.0
        let top = 16.0
        let bottom = 42.0
        let left = 20.0
        let right = 20.0
        let plotHeight = height - top - bottom
        let plotWidth = width - left - right
        let groupWidth = plotWidth / Double(points.count)
        let maxValue = max(1, points.map { max($0.primary, $0.secondary ?? 0) }.max() ?? 1)

        var parts: [String] = [
            "<svg class=\"chart-svg\" viewBox=\"0 0 \(Int(width)) \(Int(height))\" xmlns=\"http://www.w3.org/2000/svg\">",
            "<line x1=\"\(left)\" y1=\"\(height - bottom)\" x2=\"\(width - right)\" y2=\"\(height - bottom)\" stroke=\"rgba(46,51,69,0.8)\" stroke-width=\"1\" />",
        ]

        for (index, point) in points.enumerated() {
            let centerX = left + groupWidth * Double(index) + (groupWidth / 2.0)
            let barWidth = min(18.0, groupWidth * 0.26)
            let gap = 4.0

            let primaryHeight = plotHeight * Double(point.primary) / Double(maxValue)
            let primaryY = top + (plotHeight - primaryHeight)
            let primaryX = centerX - barWidth - (gap / 2.0)

            parts.append(
                "<rect x=\"\(primaryX)\" y=\"\(primaryY)\" width=\"\(barWidth)\" height=\"\(primaryHeight)\" rx=\"6\" fill=\"rgba(108, 92, 231, 0.82)\" />"
            )

            if let secondary = point.secondary {
                let secondaryHeight = plotHeight * Double(secondary) / Double(maxValue)
                let secondaryY = top + (plotHeight - secondaryHeight)
                let secondaryX = centerX + (gap / 2.0)
                parts.append(
                    "<rect x=\"\(secondaryX)\" y=\"\(secondaryY)\" width=\"\(barWidth)\" height=\"\(secondaryHeight)\" rx=\"6\" fill=\"rgba(0, 184, 148, 0.82)\" />"
                )
            }

            parts.append(
                "<text x=\"\(centerX)\" y=\"\(height - 14)\" text-anchor=\"middle\" fill=\"#8b8fa3\" font-size=\"10\" font-family=\"-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif\">\(htmlEscaped(point.label))</text>"
            )
        }

        parts.append("</svg>")
        return parts.joined()
    }

    private static func renderSingleBarChart(points: [DashboardBarPoint], emptyMessage: String) -> String {
        guard !points.isEmpty else {
            return "<div class=\"chart-empty\">\(htmlEscaped(emptyMessage))</div>"
        }

        let width = 900.0
        let height = 260.0
        let top = 16.0
        let bottom = 42.0
        let left = 20.0
        let right = 20.0
        let plotHeight = height - top - bottom
        let plotWidth = width - left - right
        let barWidth = plotWidth / Double(max(points.count, 1))
        let maxValue = max(1, points.map(\.primary).max() ?? 1)

        var parts: [String] = [
            "<svg class=\"chart-svg\" viewBox=\"0 0 \(Int(width)) \(Int(height))\" xmlns=\"http://www.w3.org/2000/svg\">",
            "<line x1=\"\(left)\" y1=\"\(height - bottom)\" x2=\"\(width - right)\" y2=\"\(height - bottom)\" stroke=\"rgba(46,51,69,0.8)\" stroke-width=\"1\" />",
        ]

        for (index, point) in points.enumerated() {
            let x = left + (barWidth * Double(index)) + (barWidth * 0.15)
            let usableWidth = max(8.0, barWidth * 0.7)
            let barHeightValue = plotHeight * Double(point.primary) / Double(maxValue)
            let y = top + (plotHeight - barHeightValue)

            parts.append(
                "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(usableWidth)\" height=\"\(barHeightValue)\" rx=\"4\" fill=\"rgba(162, 155, 254, 0.8)\" />"
            )
            parts.append(
                "<text x=\"\(x + usableWidth / 2.0)\" y=\"\(height - 14)\" text-anchor=\"middle\" fill=\"#8b8fa3\" font-size=\"10\" font-family=\"-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif\">\(htmlEscaped(point.label))</text>"
            )
        }

        parts.append("</svg>")
        return parts.joined()
    }

    private static func renderDonutChart(segments: [DashboardDonutSegment], emptyMessage: String) -> String {
        guard !segments.isEmpty else {
            return "<div class=\"chart-empty\">\(htmlEscaped(emptyMessage))</div>"
        }

        let size = 200.0
        let center = size / 2.0
        let radius = 68.0
        let strokeWidth = 22.0
        let circumference = 2.0 * Double.pi * radius
        let total = max(1, segments.reduce(0) { $0 + $1.value })
        var offset = 0.0

        let circles = segments.map { segment -> String in
            let length = circumference * (Double(segment.value) / Double(total))
            defer { offset += length }
            return """
            <circle
              cx="\(center)"
              cy="\(center)"
              r="\(radius)"
              fill="transparent"
              stroke="\(segment.colorHex)"
              stroke-width="\(strokeWidth)"
              stroke-dasharray="\(length) \(circumference - length)"
              stroke-dashoffset="\(-offset)"
            />
            """
        }.joined()

        let legend = segments.map { segment in
            """
            <div class="donut-item">
              <span><strong>\(htmlEscaped(segment.icon)) \(htmlEscaped(segment.label))</strong></span>
              <span>\(segment.value)</span>
            </div>
            """
        }.joined()

        return """
        <div class="donut-layout">
          <svg class="chart-svg" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg" style="max-width:220px;">
            <g transform="rotate(-90 100 100)">
              <circle cx="100" cy="100" r="\(radius)" fill="transparent" stroke="rgba(46,51,69,0.9)" stroke-width="\(strokeWidth)" />
              \(circles)
            </g>
            <text x="100" y="94" text-anchor="middle" fill="#e4e6f0" font-size="24" font-weight="700" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif">\(total)</text>
            <text x="100" y="116" text-anchor="middle" fill="#8b8fa3" font-size="11" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif">total</text>
          </svg>
          <div class="donut-legend">\(legend)</div>
        </div>
        """
    }

    private static func renderList(items: [DashboardListItem], emptyMessage: String) -> String {
        guard !items.isEmpty else {
            return "<div class=\"list-empty\">\(htmlEscaped(emptyMessage))</div>"
        }

        return items.map { item in
            let meta = item.metaText.map {
                "<div class=\"task-meta\">\(htmlEscaped($0))</div>"
            } ?? ""
            let badge = item.badgeText.flatMap { text -> String? in
                guard let style = item.badgeStyle else { return nil }
                return "<span class=\"badge \(style.cssClass)\">\(htmlEscaped(text))</span>"
            } ?? ""

            return """
            <div class="task-item">
              <span class="task-emoji">\(htmlEscaped(item.icon))</span>
              <div class="task-body">
                <div class="task-text">\(htmlEscaped(item.text))</div>
                \(meta)
              </div>
              <span class="task-date">\(badge)</span>
            </div>
            """
        }.joined()
    }
}

// MARK: - StashFileParser

private enum StashFileParser {

    private static func dayFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd/MM/yyyy"
        return fmt
    }

    private static func doneFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd/MM/yyyy"
        return fmt
    }

    private static func reminderFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd/MM/yyyy HH:mm"
        return fmt
    }

    private static func parseHeaderDate(from line: String) -> Date? {
        let prefix = "📅 "
        guard line.hasPrefix(prefix) else { return nil }
        let remainder = String(line.dropFirst(prefix.count))
        let dateText = remainder.split(separator: " ").first.map(String.init) ?? remainder
        return dayFormatter().date(from: dateText)
    }

    private static func dayHeader(for date: Date) -> String {
        "📅 \(dayFormatter().string(from: date))"
    }

    private static func lineMatchesDayHeader(_ line: String, date: Date) -> Bool {
        guard let headerDate = parseHeaderDate(from: line) else { return false }
        return Calendar.current.isDate(headerDate, inSameDayAs: date)
    }

    private static func parseCarryoverTags(from text: String) -> (text: String, carriedFromDate: Date?, carryoverToDate: Date?) {
        let pattern = #" \[(carried-from|carryover-to):(\d{2}/\d{2}/\d{4})\]$"#
        let dateFormatter = dayFormatter()
        var working = text
        var carriedFromDate: Date?
        var carryoverToDate: Date?

        while let range = working.range(of: pattern, options: .regularExpression) {
            let match = String(working[range])
            let body = match.dropFirst(2).dropLast()
            let parts = body.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let parsedDate = dateFormatter.date(from: String(parts[1])) {
                switch parts[0] {
                case "carried-from":
                    carriedFromDate = parsedDate
                case "carryover-to":
                    carryoverToDate = parsedDate
                default:
                    break
                }
            }
            working.removeSubrange(range)
        }

        return (working, carriedFromDate, carryoverToDate)
    }

    private static func serializeEntryLine(
        icon: String,
        text: String,
        carriedFromDate: Date?,
        carryoverToDate: Date?,
        reminderDate: Date?,
        doneDate: Date?
    ) -> String {
        let dayFmt = dayFormatter()
        let reminderFmt = reminderFormatter()
        let doneFmt = doneFormatter()

        var line = "\(icon) \(text)"
        if let carriedFromDate {
            line += " [carried-from:\(dayFmt.string(from: carriedFromDate))]"
        }
        if let carryoverToDate {
            line += " [carryover-to:\(dayFmt.string(from: carryoverToDate))]"
        }
        if let reminderDate {
            line += " ⏰ \(reminderFmt.string(from: reminderDate))"
        }
        if let doneDate {
            line += " ✅ \(doneFmt.string(from: doneDate))"
        }

        return "    \(line)"
    }

    private static func readLines(from path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return content.components(separatedBy: "\n")
        } catch {
            throw ReviewCarryoverError.unreadableFile
        }
    }

    private static func writeLines(_ lines: [String], to path: String) throws {
        let url = URL(fileURLWithPath: path)

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ReviewCarryoverError.writeFailed
        }
    }

    private static func insertEntryLine(_ entryLine: String, for date: Date, into lines: inout [String]) {
        if let headerIndex = lines.firstIndex(where: { lineMatchesDayHeader($0, date: date) }) {
            var insertIndex = headerIndex + 1
            while insertIndex < lines.count {
                let trimmed = lines[insertIndex].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || lines[insertIndex].hasPrefix("📅") { break }
                insertIndex += 1
            }
            lines.insert(entryLine, at: insertIndex)
            return
        }

        let header = dayHeader(for: date)
        if lines.isEmpty {
            lines = [header, entryLine]
        } else {
            lines.insert(contentsOf: [header, entryLine, ""], at: 0)
        }
    }

    static func appendTaskLine(_ task: String, reminderDate: Date?, for date: Date, in path: String) throws {
        var lines = try readLines(from: path)
        let entryLine = serializeEntryLine(
            icon: String(task.prefix(1)),
            text: String(task.dropFirst().trimmingCharacters(in: .whitespaces)),
            carriedFromDate: nil,
            carryoverToDate: nil,
            reminderDate: reminderDate,
            doneDate: nil
        )
        insertEntryLine(entryLine, for: date, into: &lines)
        try writeLines(lines, to: path)
    }

    static func carryForward(entry: StashEntry, in path: String) throws {
        guard !entry.isDone else { throw ReviewCarryoverError.invalidSourceEntry }
        guard entry.carryoverToDate == nil else { throw ReviewCarryoverError.alreadyCarriedForward }
        guard let targetDate = Calendar.current.date(byAdding: .day, value: 1, to: entry.dayDate) else {
            throw ReviewCarryoverError.invalidSourceEntry
        }

        var lines = try readLines(from: path)
        guard entry.lineIndex < lines.count, lines[entry.lineIndex].hasPrefix("    ") else {
            throw ReviewCarryoverError.invalidSourceEntry
        }

        lines[entry.lineIndex] = serializeEntryLine(
            icon: entry.icon,
            text: entry.text,
            carriedFromDate: nil,
            carryoverToDate: targetDate,
            reminderDate: entry.reminderDate,
            doneDate: entry.doneDate
        )

        let copiedLine = serializeEntryLine(
            icon: entry.icon,
            text: entry.text,
            carriedFromDate: entry.dayDate,
            carryoverToDate: nil,
            reminderDate: entry.reminderDate,
            doneDate: nil
        )
        insertEntryLine(copiedLine, for: targetDate, into: &lines)
        try writeLines(lines, to: path)
    }

    static func parse(from path: String) -> [DayBlock] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n")
        var blocks: [DayBlock] = []
        var currentDate: Date? = nil
        var currentEntries: [StashEntry] = []
        let doneFmt = doneFormatter()
        let reminderFmt = reminderFormatter()

        for (idx, line) in lines.enumerated() {
            // Day header: "📅 dd/MM/yyyy"
            if line.hasPrefix("📅 ") {
                if let date = currentDate {
                    blocks.append(DayBlock(date: date, entries: currentEntries))
                }
                currentDate = parseHeaderDate(from: line)
                currentEntries = []
                continue
            }

            // Entry line: "    <emoji> <text>[ ✅ dd/MM/yyyy]"
            guard line.hasPrefix("    "), currentDate != nil else { continue }
            let stripped = String(line.dropFirst(4))
            guard !stripped.isEmpty else { continue }

            // Extract first grapheme cluster as the icon emoji
            let iconEndIdx = stripped.index(after: stripped.startIndex)
            let iconStr = String(stripped[..<iconEndIdx])
            let restStartIdx = iconEndIdx

            // rest is " <text>[ ✅ dd/MM/yyyy]"
            guard restStartIdx < stripped.endIndex else { continue }
            let rest = String(stripped[restStartIdx...]).trimmingCharacters(in: .init(charactersIn: " "))

            // Check for done marker at end: " ✅ dd/MM/yyyy"
            var taskText = rest
            var isDone = false
            var doneDate: Date? = nil

            let doneMarker = " ✅ "
            if let doneRange = rest.range(of: doneMarker, options: .backwards) {
                let afterMarker = String(rest[doneRange.upperBound...])
                if let parsedDate = doneFmt.date(from: afterMarker) {
                    isDone = true
                    doneDate = parsedDate
                    taskText = String(rest[..<doneRange.lowerBound])
                }
            }

            // Check for reminder date marker: " ⏰ dd/MM/yyyy HH:mm"
            var reminderDate: Date? = nil
            let reminderMarker = " ⏰ "
            if let remRange = taskText.range(of: reminderMarker, options: .backwards) {
                let afterMarker = String(taskText[remRange.upperBound...])
                if let parsedDate = reminderFmt.date(from: afterMarker) {
                    reminderDate = parsedDate
                    taskText = String(taskText[..<remRange.lowerBound])
                }
            }

             let carryover = parseCarryoverTags(from: taskText)
             taskText = carryover.text

            currentEntries.append(StashEntry(
                dayDate: currentDate!,
                lineIndex: idx,
                icon: iconStr,
                text: taskText,
                isDone: isDone,
                doneDate: doneDate,
                reminderDate: reminderDate,
                carriedFromDate: carryover.carriedFromDate,
                carryoverToDate: carryover.carryoverToDate
            ))
        }

        if let date = currentDate {
            blocks.append(DayBlock(date: date, entries: currentEntries))
        }

        return blocks
    }

    static func blocks(for period: ReviewPeriod, allBlocks: [DayBlock]) -> [DayBlock] {
        let cal = Calendar.current
        switch period {
        case .day(let date):
            return allBlocks.filter { cal.isDate($0.date, inSameDayAs: date) }
        case .week(let start, let end):
            return allBlocks.filter { block in
                let d = block.date
                return d >= cal.startOfDay(for: start) && d <= cal.startOfDay(for: end)
            }.sorted { $0.date > $1.date }
        }
    }

    static func toggleDone(lineIndex: Int, completed: Bool, date: Date, in path: String) {
        guard var content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }

        let doneFmt = DateFormatter()
        doneFmt.locale = Locale(identifier: "en_US_POSIX")
        doneFmt.dateFormat = "dd/MM/yyyy"
        let doneMarker = " ✅ "
        let dateSuffix = doneFmt.string(from: date)

        var line = lines[lineIndex]
        if completed {
            // Remove existing marker first (idempotent), then append
            if let range = line.range(of: doneMarker, options: .backwards) {
                let afterMarker = String(line[range.upperBound...])
                if doneFmt.date(from: afterMarker) != nil {
                    line = String(line[..<range.lowerBound])
                }
            }
            line += "\(doneMarker)\(dateSuffix)"
        } else {
            if let range = line.range(of: doneMarker, options: .backwards) {
                let afterMarker = String(line[range.upperBound...])
                if doneFmt.date(from: afterMarker) != nil {
                    line = String(line[..<range.lowerBound])
                }
            }
        }

        lines[lineIndex] = line
        content = lines.joined(separator: "\n")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - RewindScheduler

private enum RewindScheduler {

    // MARK: Date helper

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // MARK: Reviewed-state (UserDefaults + file)

    static func isTodayReviewed() -> Bool {
        return UserDefaults.standard.string(forKey: kRewindReviewedDateKey) == todayString()
    }

    /// Appends the reviewed emoji to today's header line in the task file and persists the date.
    static func markTodayReviewed() {
        let url = URL(fileURLWithPath: taskFilePath)
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "dd/MM/yyyy"
        let todayHeader = "📅 \(dateFmt.string(from: Date()))"

        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = content.components(separatedBy: "\n")

        if let idx = lines.firstIndex(where: { $0.hasPrefix(todayHeader) }) {
            // Only append if not already marked
            if !lines[idx].contains(kRewindReviewedEmoji) {
                lines[idx] = lines[idx] + " \(kRewindReviewedEmoji)"
                content = lines.joined(separator: "\n")
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        UserDefaults.standard.set(todayString(), forKey: kRewindReviewedDateKey)
        // Cancel any pending snooze notification now that day is reviewed
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [kRewindSnoozeNotificationID])
    }

    // MARK: Snooze counter (resets per calendar day)

    static func snoozesToday() -> Int {
        let storedDate = UserDefaults.standard.string(forKey: kRewindSnoozeDateKey) ?? ""
        if storedDate != todayString() { return 0 }
        return UserDefaults.standard.integer(forKey: kRewindSnoozeCountKey)
    }

    static func incrementSnooze() {
        let today = todayString()
        let storedDate = UserDefaults.standard.string(forKey: kRewindSnoozeDateKey) ?? ""
        let current = (storedDate == today) ? UserDefaults.standard.integer(forKey: kRewindSnoozeCountKey) : 0
        UserDefaults.standard.set(current + 1, forKey: kRewindSnoozeCountKey)
        UserDefaults.standard.set(today, forKey: kRewindSnoozeDateKey)
    }

    // MARK: Permission

    static func requestAuthIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: Category registration

    static func registerCategories() {
        let reviewAction  = UNNotificationAction(
            identifier: "review",
            title: L("notification.rewind.action.review"),
            options: [.foreground]
        )
        let snoozeAction  = UNNotificationAction(
            identifier: "snooze",
            title: L("notification.rewind.action.snooze"),
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: "dismiss",
            title: L("notification.rewind.action.dismiss"),
            options: [.destructive]
        )

        let withSnooze = UNNotificationCategory(
            identifier: kRewindCategoryWithSnooze,
            actions: [reviewAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let noSnooze = UNNotificationCategory(
            identifier: kRewindCategoryNoSnooze,
            actions: [reviewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([withSnooze, noSnooze])
    }

    // MARK: Scheduling

    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        // Remove previous daily notification before rescheduling
        center.removePendingNotificationRequests(withIdentifiers: [kRewindNotificationID])

        let content = UNMutableNotificationContent()
        content.title = L("notification.rewind.title")
        content.body  = L("notification.rewind.body")
        content.sound = .default
        content.categoryIdentifier = kRewindCategoryWithSnooze

        var components = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: kRewindNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [kRewindNotificationID, kRewindSnoozeNotificationID]
        )
    }

    /// Schedule a snooze notification 1 hour from now.
    /// `currentSnoozeCount` is the count BEFORE incrementing (0-based: 0 or 1 means still can snooze).
    static func scheduleSnooze(afterIncrementCount snoozeCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [kRewindSnoozeNotificationID])

        let content = UNMutableNotificationContent()
        content.title = L("notification.rewind.title")
        content.body  = L("notification.rewind.body")
        content.sound = .default
        // If user has snoozed twice already, next notification has no snooze option
        content.categoryIdentifier = snoozeCount >= 2 ? kRewindCategoryNoSnooze : kRewindCategoryWithSnooze

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: kRewindSnoozeNotificationID,
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }
}

// MARK: - ReviewWindowController

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class ReviewRowView: NSView {
    private let toggleBtn: NSButton
    private let iconLabel: NSTextField
    private let textLabel: NSTextField
    private var reminderDateLabel: NSTextField?
    private var scheduledTagLabel: NSTextField?
    private var carryoverTagLabel: NSTextField?
    private var carryoverButton: NSButton?
    private var entry: StashEntry
    private let onToggle: (Bool) -> Void
    private let onCarryForward: ((StashEntry) -> Void)?

    static func rowHeight(for entry: StashEntry) -> CGFloat {
        entry.reminderDate != nil ? 42 : 28
    }

    /// Returns true if this entry is a reminder with a future date (day-level comparison).
    private var isFutureReminder: Bool {
        guard entry.icon == "🔔", let rd = entry.reminderDate else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let rdDay = cal.startOfDay(for: rd)
        return rdDay > today
    }

    private var shouldShowCarryForwardAction: Bool {
        onCarryForward != nil && !entry.isDone
    }

    private var isCarryForwardDisabled: Bool {
        isFutureReminder || entry.carryoverToDate != nil
    }

    private var carryoverTagConfiguration: (text: String, color: NSColor, tooltip: String)? {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none

        if let carryoverToDate = entry.carryoverToDate {
            return (
                L("review.carryover.postponed.tag"),
                .systemIndigo,
                LF("review.carryover.postponed.tooltip", fmt.string(from: carryoverToDate))
            )
        }

        if let carriedFromDate = entry.carriedFromDate {
            return (
                L("review.carryover.copied.tag"),
                .systemBlue,
                LF("review.carryover.copied.tooltip", fmt.string(from: carriedFromDate))
            )
        }

        return nil
    }

    init(entry: StashEntry, width: CGFloat, onToggle: @escaping (Bool) -> Void, onCarryForward: ((StashEntry) -> Void)? = nil) {
        self.entry = entry
        self.onToggle = onToggle
        self.onCarryForward = onCarryForward

        toggleBtn = NSButton()
        iconLabel = NSTextField(labelWithString: entry.icon)
        textLabel = NSTextField(labelWithString: entry.text)

        let h = ReviewRowView.rowHeight(for: entry)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeTagLabel(text: String, backgroundColor: NSColor) -> NSTextField {
        let tag = NSTextField(labelWithString: text)
        tag.font = .systemFont(ofSize: 9, weight: .semibold)
        tag.textColor = .white
        tag.backgroundColor = backgroundColor
        tag.drawsBackground = true
        tag.isBezeled = false
        tag.alignment = .center
        tag.wantsLayer = true
        tag.layer?.cornerRadius = 3
        tag.sizeToFit()
        return tag
    }

    private func buildUI() {
        let pad: CGFloat = 8
        let toggleW: CGFloat = 24
        let iconW: CGFloat = 26
        let hasRemDate = entry.reminderDate != nil

        // Vertical positions: shift content up when there's a reminder date below
        let contentY: CGFloat = hasRemDate ? 22 : 5
        let contentH: CGFloat = hasRemDate ? 16 : 18
        let toggleY: CGFloat = hasRemDate ? 11 : 4

        toggleBtn.frame = NSRect(x: pad, y: toggleY, width: toggleW, height: 20)
        toggleBtn.bezelStyle = .inline
        toggleBtn.isBordered = false
        toggleBtn.focusRingType = .none
        toggleBtn.font = .systemFont(ofSize: 14)
        toggleBtn.target = self
        toggleBtn.action = #selector(didToggle)
        toggleBtn.setAccessibilityLabel(L("review.done.accessibility"))
        addSubview(toggleBtn)

        iconLabel.frame = NSRect(x: pad + toggleW + 4, y: contentY, width: iconW, height: contentH)
        iconLabel.font = .systemFont(ofSize: 13)
        iconLabel.alignment = .center
        addSubview(iconLabel)

        let textX = pad + toggleW + 4 + iconW + 4
        var trailingX = frame.width - pad

        if shouldShowCarryForwardAction {
            let button = NSButton(frame: .zero)
            button.title = L("review.carryover.action")
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(didCarryForward)
            button.setAccessibilityLabel(L("review.carryover.action.accessibility"))
            button.sizeToFit()
            let buttonWidth = max(84, button.frame.width + 18)
            button.frame = NSRect(x: trailingX - buttonWidth, y: toggleY - 1, width: buttonWidth, height: 22)
            carryoverButton = button
            addSubview(button)
            trailingX = button.frame.minX - 6
        }

        if let carryoverTag = carryoverTagConfiguration {
            let tag = makeTagLabel(text: carryoverTag.text, backgroundColor: carryoverTag.color)
            let tagW = tag.frame.width + 10
            tag.frame = NSRect(x: trailingX - tagW, y: contentY + 1, width: tagW, height: 14)
            tag.toolTip = carryoverTag.tooltip
            carryoverTagLabel = tag
            addSubview(tag)
            trailingX = tag.frame.minX - 6
        }

        textLabel.frame = NSRect(x: textX, y: contentY, width: max(96, trailingX - textX), height: contentH)
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.lineBreakMode = .byTruncatingTail
        addSubview(textLabel)

        if let rd = entry.reminderDate {
            let rdFmt = DateFormatter()
            rdFmt.dateStyle = .short
            rdFmt.timeStyle = .short
            let rdLabel = NSTextField(labelWithString: "⏰ \(rdFmt.string(from: rd))")
            rdLabel.frame = NSRect(x: textX, y: 5, width: frame.width - textX - pad, height: 14)
            rdLabel.font = .systemFont(ofSize: 10)
            rdLabel.textColor = .secondaryLabelColor
            reminderDateLabel = rdLabel
            addSubview(rdLabel)

            if isFutureReminder {
                let tag = makeTagLabel(text: L("review.scheduled.tag"), backgroundColor: .systemOrange)
                let tagW = tag.frame.width + 8
                let tagH: CGFloat = 14
                tag.frame = NSRect(x: frame.width - pad - tagW, y: 5, width: tagW, height: tagH)
                scheduledTagLabel = tag
                addSubview(tag)
            }
        }

        refreshState()
    }

    private func refreshState() {
        if isFutureReminder {
            toggleBtn.title = "○"
            toggleBtn.isEnabled = false
            toggleBtn.alphaValue = 0.3
            textLabel.textColor = .secondaryLabelColor
        } else if entry.isDone {
            toggleBtn.title = "✅"
            toggleBtn.isEnabled = true
            toggleBtn.alphaValue = 1.0
            textLabel.textColor = .tertiaryLabelColor
        } else {
            toggleBtn.title = "○"
            toggleBtn.isEnabled = true
            toggleBtn.alphaValue = 1.0
            textLabel.textColor = .labelColor
        }

        if let carryoverButton {
            carryoverButton.isEnabled = shouldShowCarryForwardAction && !isCarryForwardDisabled
            carryoverButton.alphaValue = carryoverButton.isEnabled ? 1.0 : 0.45
        }
    }

    @objc private func didToggle() {
        entry.isDone.toggle()
        let date = entry.doneDate ?? Date()
        StashFileParser.toggleDone(lineIndex: entry.lineIndex, completed: entry.isDone, date: date, in: taskFilePath)
        if entry.isDone {
            entry.doneDate = Date()
        } else {
            entry.doneDate = nil
        }
        refreshState()
        onToggle(entry.isDone)
    }

    @objc private func didCarryForward() {
        guard !isCarryForwardDisabled else { return }
        onCarryForward?(entry)
    }
}

final class ReviewWindowController: NSWindowController {
    private let period: ReviewPeriod
    private let isFromNotification: Bool
    private var stackView: NSStackView!
    private let W: CGFloat = 500
    private let H: CGFloat = 540

    fileprivate init(period: ReviewPeriod, fromNotification: Bool = false) {
        self.period = period
        self.isFromNotification = fromNotification
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("review.window.title")
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 16

        // Title
        let titleLabel = NSTextField(labelWithString: titleText())
        titleLabel.frame = NSRect(x: pad, y: H - 48, width: W - pad * 2, height: 24)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.lineBreakMode = .byWordWrapping
        cv.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: subtitleText())
        subtitleLabel.frame = NSRect(x: pad, y: H - 76, width: W - pad * 2, height: 22)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        cv.addSubview(subtitleLabel)

        // Separator
        let sep = NSBox()
        sep.frame = NSRect(x: pad, y: H - 88, width: W - pad * 2, height: 1)
        sep.boxType = .separator
        cv.addSubview(sep)

        // Scroll + Stack
        let scrollH = H - 88 - 46 - 8
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 46, width: W, height: scrollH))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // FlippedClipView inverts AppKit's default bottom-left origin so items appear at the top
        let flippedClip = FlippedClipView()
        flippedClip.drawsBackground = false
        scrollView.contentView = flippedClip
        scrollView.documentView = stackView
        let clipView = flippedClip
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])
        cv.addSubview(scrollView)

        // "Mark day as reviewed" button — only when opened from notification
        if isFromNotification {
            let markBtn = NSButton(frame: NSRect(x: pad, y: pad, width: W - pad * 2 - 100, height: 26))
            markBtn.title = L("review.markReviewed")
            markBtn.bezelStyle = .rounded
            markBtn.target = self
            markBtn.action = #selector(markDayReviewed)
            cv.addSubview(markBtn)
        }

        // Close button
        let closeBtn = NSButton(frame: NSRect(x: W - pad - 90, y: pad, width: 90, height: 26))
        closeBtn.title = L("common.close")
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.target = self
        closeBtn.action = #selector(closeWindow)
        cv.addSubview(closeBtn)

        populateList()
    }

    private func reloadList() {
        for arrangedSubview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        populateList()
    }

    private func presentCarryoverError(_ error: ReviewCarryoverError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("review.carryover.error.title")
        alert.informativeText = carryoverErrorMessage(error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func handleCarryForward(_ entry: StashEntry) {
        do {
            try StashFileParser.carryForward(entry: entry, in: taskFilePath)
            reloadList()
        } catch let error as ReviewCarryoverError {
            presentCarryoverError(error)
        } catch {
            presentCarryoverError(.writeFailed)
        }
    }

    private func populateList() {
        let allBlocks = StashFileParser.parse(from: taskFilePath)
        let periodBlocks = StashFileParser.blocks(for: period, allBlocks: allBlocks)

        // For .day, if no block exists, show empty state
        if periodBlocks.isEmpty {
            addEmptyLabel()
            return
        }

        // dateFmt for display — uses system locale so dates appear localized
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .short
        dateFmt.timeStyle = .none

        for block in periodBlocks {
            // Day header — only for weekly view
            if case .week = period {
                let header = NSTextField(labelWithString: "📅 \(dateFmt.string(from: block.date))")
                header.font = .boldSystemFont(ofSize: 13)
                header.textColor = .secondaryLabelColor
                header.translatesAutoresizingMaskIntoConstraints = false
                let headerContainer = NSView()
                headerContainer.translatesAutoresizingMaskIntoConstraints = false
                headerContainer.addSubview(header)
                NSLayoutConstraint.activate([
                    headerContainer.widthAnchor.constraint(equalToConstant: W),
                    headerContainer.heightAnchor.constraint(equalToConstant: 30),
                    header.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 12),
                    header.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
                ])
                stackView.addArrangedSubview(headerContainer)
            }

            if block.entries.isEmpty {
                let isWeek: Bool
                if case .week = period { isWeek = true } else { isWeek = false }
                addEmptyLabel(indent: isWeek)
            } else {
                let showCarryForwardAction: Bool
                if case .day = period {
                    showCarryForwardAction = true
                } else {
                    showCarryForwardAction = false
                }

                for entry in block.entries {
                    let rowH = ReviewRowView.rowHeight(for: entry)
                    let row = ReviewRowView(
                        entry: entry,
                        width: W,
                        onToggle: { _ in },
                        onCarryForward: showCarryForwardAction ? { [weak self] entry in
                            self?.handleCarryForward(entry)
                        } : nil
                    )
                    row.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        row.widthAnchor.constraint(equalToConstant: W),
                        row.heightAnchor.constraint(equalToConstant: rowH),
                    ])

                    // Row separator
                    let rowSep = NSBox()
                    rowSep.boxType = .separator
                    rowSep.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        rowSep.widthAnchor.constraint(equalToConstant: W - 24),
                        rowSep.heightAnchor.constraint(equalToConstant: 1),
                    ])

                    stackView.addArrangedSubview(row)
                    stackView.addArrangedSubview(rowSep)
                }
            }
        }
    }

    private func addEmptyLabel(indent: Bool = false) {
        let emptyLabel = NSTextField(labelWithString: L("review.empty"))
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: W),
            container.heightAnchor.constraint(equalToConstant: 28),
            emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indent ? 24 : 12),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        stackView.addArrangedSubview(container)
    }

    private func titleText() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        switch period {
        case .day(let date):
            return LF("review.title.day", fmt.string(from: date))
        case .week(let start, let end):
            fmt.dateStyle = .none
            fmt.setLocalizedDateFormatFromTemplate("dd/MM")
            return LF("review.title.week", fmt.string(from: start), fmt.string(from: end))
        }
    }

    private func subtitleText() -> String {
        switch period {
        case .day: return L("review.subtitle.day")
        case .week: return L("review.subtitle.week")
        }
    }

    @objc private func markDayReviewed() {
        RewindScheduler.markTodayReviewed()
        close()
    }

    @objc private func closeWindow() { close() }
}

final class DashboardWindowController: NSWindowController {
    private var periodPopup: NSPopUpButton!
    private var fromLabel: NSTextField!
    private var fromPicker: NSDatePicker!
    private var toLabel: NSTextField!
    private var toPicker: NSDatePicker!
    private var webView: WKWebView!
    private var presets: [DashboardPeriodPreset] {
        DashboardAccessLevel.current().allowedPresets
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("dashboard.window.title")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    func reloadDashboard() {
        reloadPresetOptions()
        let summary = DashboardDataBuilder.build(
            preset: selectedPreset(),
            customStart: fromPicker.dateValue,
            customEnd: toPicker.dateValue
        )
        webView.loadHTMLString(DashboardHTMLRenderer.render(summary: summary), baseURL: Bundle.main.resourceURL)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let topBarHeight: CGFloat = 58

        let separator = NSBox(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - topBarHeight - 1,
            width: contentView.bounds.width,
            height: 1
        ))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(separator)

        let topBar = NSView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - topBarHeight,
            width: contentView.bounds.width,
            height: topBarHeight
        ))
        topBar.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(topBar)

        let periodLabel = NSTextField(labelWithString: L("dashboard.filter.label"))
        periodLabel.frame = NSRect(x: 18, y: 20, width: 48, height: 18)
        periodLabel.font = .systemFont(ofSize: 12)
        periodLabel.textColor = .secondaryLabelColor
        topBar.addSubview(periodLabel)

        periodPopup = NSPopUpButton(frame: NSRect(x: 72, y: 15, width: 170, height: 28), pullsDown: false)
        periodPopup.target = self
        periodPopup.action = #selector(periodChanged)
        topBar.addSubview(periodPopup)

        fromLabel = NSTextField(labelWithString: L("dashboard.filter.from"))
        fromLabel.frame = NSRect(x: 260, y: 20, width: 40, height: 18)
        fromLabel.font = .systemFont(ofSize: 12)
        fromLabel.textColor = .secondaryLabelColor
        topBar.addSubview(fromLabel)

        fromPicker = NSDatePicker(frame: NSRect(x: 304, y: 15, width: 120, height: 26))
        fromPicker.datePickerStyle = .textFieldAndStepper
        fromPicker.datePickerElements = .yearMonthDay
        fromPicker.target = self
        fromPicker.action = #selector(customDateChanged)
        topBar.addSubview(fromPicker)

        toLabel = NSTextField(labelWithString: L("dashboard.filter.to"))
        toLabel.frame = NSRect(x: 438, y: 20, width: 22, height: 18)
        toLabel.font = .systemFont(ofSize: 12)
        toLabel.textColor = .secondaryLabelColor
        topBar.addSubview(toLabel)

        toPicker = NSDatePicker(frame: NSRect(x: 466, y: 15, width: 120, height: 26))
        toPicker.datePickerStyle = .textFieldAndStepper
        toPicker.datePickerElements = .yearMonthDay
        toPicker.target = self
        toPicker.action = #selector(customDateChanged)
        topBar.addSubview(toPicker)

        let today = Calendar.current.startOfDay(for: Date())
        fromPicker.dateValue = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        toPicker.dateValue = today

        webView = WKWebView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - topBarHeight - 1
        ))
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)

        reloadPresetOptions(selected: .last7Days)
        updateCustomControlsVisibility()
        reloadDashboard()
    }

    @objc private func periodChanged() {
        updateCustomControlsVisibility()
        reloadDashboard()
    }

    @objc private func customDateChanged() {
        if fromPicker.dateValue > toPicker.dateValue {
            toPicker.dateValue = fromPicker.dateValue
        }
        reloadDashboard()
    }

    private func selectedPreset() -> DashboardPeriodPreset {
        let index = periodPopup.indexOfSelectedItem
        guard index >= 0, index < presets.count else { return .last7Days }
        return presets[index]
    }

    private func reloadPresetOptions(selected preferred: DashboardPeriodPreset? = nil) {
        let desired = preferred ?? selectedPreset()
        let allowedPresets = presets
        let selectedIndex = allowedPresets.firstIndex(of: desired) ?? 0
        periodPopup.removeAllItems()
        periodPopup.addItems(withTitles: allowedPresets.map(\.displayName))
        periodPopup.selectItem(at: selectedIndex)
    }

    private func updateCustomControlsVisibility() {
        let isCustom = selectedPreset() == .custom
        fromLabel.isHidden = !isCustom
        fromPicker.isHidden = !isCustom
        toLabel.isHidden = !isCustom
        toPicker.isHidden = !isCustom
    }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onboardingWindowController: OnboardingWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var helpWindowController: HelpWindowController?
    private var reviewWindowController: ReviewWindowController?
    private var dashboardWindowController: DashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPopover()
        setupHotkey()
        setupNotifications()
        LicenseManager.refreshEntitlementIfNeeded()
        if shouldPresentOnboardingOnLaunch() {
            showOnboarding()
        } else if !isAccessibilityTrusted() {
            promptAccessibilityTrustDialog()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LicenseManager.refreshEntitlementIfNeeded()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: L("menu.edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L("menu.edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        RewindScheduler.registerCategories()
        // Re-schedule on launch to survive app restarts
        let enabled = UserDefaults.standard.bool(forKey: kRewindEnabledKey)
        if enabled {
            let hour   = UserDefaults.standard.integer(forKey: kRewindHourKey)
            let minute = UserDefaults.standard.integer(forKey: kRewindMinuteKey)
            RewindScheduler.schedule(hour: hour == 0 && minute == 0 ? kRewindDefaultHour : hour,
                                     minute: hour == 0 && minute == 0 ? kRewindDefaultMinute : minute)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        if let icon = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: L("app.name")) {
            icon.isTemplate = true  // adapta automaticamente ao tema claro/escuro
            btn.image = icon
        }
        btn.target = self
        btn.action = #selector(statusButtonClicked(_:))
        btn.sendAction(on: [.leftMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentViewController = TaskViewController()
        popover.behavior = .transient
        popover.animates = true
    }

    func onboardingDidComplete() {
        UserDefaults.standard.set(true, forKey: kOnboardingCompletedDefaultsKey)
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }

    func accessibilityGranted() -> Bool {
        isAccessibilityTrusted()
    }

    func promptAccessibility() {
        promptAccessibilityTrustDialog()
    }

    @objc private func showOnboarding() {
        if let ctrl = onboardingWindowController, ctrl.window?.isVisible == true {
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == kHotkeyMask,
                  e.keyCode == kHotkeyCode else { return }
            DispatchQueue.main.async { self?.showPopover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == kHotkeyMask,
                  e.keyCode == kHotkeyCode else { return e }
            DispatchQueue.main.async { self?.showPopover() }
            return nil
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let openItem = menu.addItem(
            withTitle: L("menu.openTaskFile"),
            action: #selector(openTaskFile),
            keyEquivalent: ""
        )
        openItem.target = self

        // Review submenu
        let reviewItem = NSMenuItem(title: L("menu.review"), action: nil, keyEquivalent: "")
        let reviewSubmenu = NSMenu(title: L("menu.review"))
        let dayItem = NSMenuItem(title: L("menu.review.day"), action: #selector(reviewDay), keyEquivalent: "")
        dayItem.target = self
        let weekItem = NSMenuItem(title: L("menu.review.week"), action: #selector(reviewWeek), keyEquivalent: "")
        weekItem.target = self
        reviewSubmenu.addItem(dayItem)
        reviewSubmenu.addItem(weekItem)
        reviewItem.submenu = reviewSubmenu
        menu.addItem(reviewItem)

        let dashboardItem = menu.addItem(
            withTitle: L("menu.dashboard"),
            action: #selector(openDashboard),
            keyEquivalent: ""
        )
        dashboardItem.target = self

        menu.addItem(.separator())
        let prefsItem = menu.addItem(
            withTitle: L("menu.preferences"),
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        let helpItem = menu.addItem(
            withTitle: L("menu.help"),
            action: #selector(showHelp),
            keyEquivalent: "h"
        )
        helpItem.target = self
        let aboutItem = menu.addItem(
            withTitle: L("menu.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        // Padrão canônico: define menu, dispara click (bloqueante até fechar), limpa
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func reviewDay() {
        openReview(period: .day(Date()))
    }

    @objc private func reviewWeek() {
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        openReview(period: .week(start: start, end: today))
    }

    private func openReview(period: ReviewPeriod, fromNotification: Bool = false) {
        if let ctrl = reviewWindowController, ctrl.window?.isVisible == true {
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        reviewWindowController = ReviewWindowController(period: period, fromNotification: fromNotification)
        reviewWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDashboard() {
        guard SubscriptionPlan.current().allowsDashboard else {
            presentDashboardPaywall()
            return
        }

        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController()
        }

        dashboardWindowController?.reloadDashboard()
        dashboardWindowController?.showWindow(nil)
        dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentDashboardPaywall() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("dashboard.paywall.title")
        alert.informativeText = L("dashboard.paywall.message")
        alert.addButton(withTitle: L("dashboard.paywall.action.upgrade"))
        alert.addButton(withTitle: L("dashboard.paywall.action.activate"))
        alert.addButton(withTitle: L("common.cancel"))

        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            LicenseManager.openUpgradePage()
        } else if result == .alertSecondButtonReturn {
            presentPreferences(selecting: .license)
        }
    }

    @objc private func openTaskFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: taskFilePath))
    }

    @objc private func showPreferences() {
        presentPreferences(selecting: .general)
    }

    private func presentPreferences(selecting pane: PreferencesPane) {
        if let ctrl = preferencesWindowController, ctrl.window?.isVisible == true {
            ctrl.selectPane(pane)
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        preferencesWindowController = PreferencesWindowController(selectedPane: pane)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.selectPane(pane)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showHelp() {
        if let ctrl = helpWindowController, ctrl.window?.isVisible == true {
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        helpWindowController = HelpWindowController()
        helpWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        showAboutPanelProxy()
    }

    @objc func showAboutPanelProxy() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: L("app.name"),
            .version: appShortVersion(),
            .applicationVersion: appBuildVersion(),
            .credits: aboutPanelCredits(),
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPopover() {
        guard let btn = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.identifier == kRewindNotificationID ||
              notification.request.identifier == kRewindSnoozeNotificationID else {
            completionHandler([.banner, .sound])
            return
        }
        // Suppress on weekends (only for the repeating daily notification)
        if notification.request.identifier == kRewindNotificationID {
            let weekday = Calendar.current.component(.weekday, from: Date())
            // weekday: 1=Sun, 2=Mon…6=Fri, 7=Sat
            guard weekday >= 2 && weekday <= 6 else {
                completionHandler([])
                return
            }
        }
        // Suppress if day already reviewed
        if RewindScheduler.isTodayReviewed() {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        guard id == kRewindNotificationID || id == kRewindSnoozeNotificationID else {
            completionHandler()
            return
        }
        switch response.actionIdentifier {
        case "review", UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async { [weak self] in
                self?.openReview(period: .day(Date()), fromNotification: true)
                completionHandler()
            }
            return
        case "snooze":
            RewindScheduler.incrementSnooze()
            RewindScheduler.scheduleSnooze(afterIncrementCount: RewindScheduler.snoozesToday())
        default:
            break // "dismiss" or UNNotificationDismissActionIdentifier — no-op
        }
        completionHandler()
    }
}

// MARK: - OnboardingWindowController
final class OnboardingWindowController: NSWindowController {
    private enum Step: Int {
        case welcome = 0
        case setup = 1
        case ai = 2
    }

    private let totalSteps = 3
    private var step: Step = .welcome

    private var progressLabel: NSTextField!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!

    private var welcomeView: NSView!
    private var setupView: NSView!
    private var aiView: NSView!

    private var accessibilityStatusLabel: NSTextField!
    private var folderField: NSTextField!

    private var providerPopup: NSPopUpButton!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!

    private var backButton: NSButton!
    private var primaryButton: NSButton!

    convenience init() {
        let W: CGFloat = 560
        let H: CGFloat = 420
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("onboarding.window.title")
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
        buildUI(W: W, H: H)
        renderStep()
    }

    private func buildUI(W: CGFloat, H: CGFloat) {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 20

        progressLabel = NSTextField(labelWithString: "")
        progressLabel.frame = NSRect(x: pad, y: H - 34, width: W - pad * 2, height: 16)
        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .secondaryLabelColor
        cv.addSubview(progressLabel)

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.frame = NSRect(x: pad, y: H - 66, width: W - pad * 2, height: 26)
        titleLabel.font = .boldSystemFont(ofSize: 20)
        cv.addSubview(titleLabel)

        subtitleLabel = NSTextField(wrappingLabelWithString: "")
        subtitleLabel.frame = NSRect(x: pad, y: H - 108, width: W - pad * 2, height: 34)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        cv.addSubview(subtitleLabel)

        let contentY: CGFloat = 86
        let contentH: CGFloat = H - 198
        welcomeView = NSView(frame: NSRect(x: pad, y: contentY, width: W - pad * 2, height: contentH))
        setupView = NSView(frame: welcomeView.frame)
        aiView = NSView(frame: welcomeView.frame)
        cv.addSubview(welcomeView)
        cv.addSubview(setupView)
        cv.addSubview(aiView)

        buildWelcomeView(in: welcomeView)
        buildSetupView(in: setupView)
        buildAIView(in: aiView)

        backButton = NSButton(frame: NSRect(x: W - pad - 180, y: 20, width: 84, height: 30))
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backTapped)
        cv.addSubview(backButton)

        primaryButton = NSButton(frame: NSRect(x: W - pad - 90, y: 20, width: 90, height: 30))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        cv.addSubview(primaryButton)

        window?.initialFirstResponder = primaryButton
    }

    private func buildWelcomeView(in view: NSView) {
        let body = NSTextField(wrappingLabelWithString: L("onboarding.welcome.body"))
        body.frame = NSRect(x: 0, y: 34, width: view.bounds.width, height: view.bounds.height - 24)
        body.font = .systemFont(ofSize: 14)
        body.alignment = .left
        view.addSubview(body)
    }

    private func buildSetupView(in view: NSView) {
        let accessibilityTitle = NSTextField(labelWithString: L("onboarding.setup.accessibility.label"))
        accessibilityTitle.frame = NSRect(x: 0, y: view.bounds.height - 36, width: view.bounds.width, height: 18)
        accessibilityTitle.font = .boldSystemFont(ofSize: 13)
        view.addSubview(accessibilityTitle)

        accessibilityStatusLabel = NSTextField(labelWithString: "")
        accessibilityStatusLabel.frame = NSRect(x: 0, y: view.bounds.height - 58, width: 280, height: 16)
        accessibilityStatusLabel.font = .systemFont(ofSize: 12)
        accessibilityStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(accessibilityStatusLabel)

        let accessibilityBtn = NSButton(frame: NSRect(x: view.bounds.width - 170, y: view.bounds.height - 64, width: 170, height: 26))
        accessibilityBtn.title = L("onboarding.setup.accessibility.button")
        accessibilityBtn.bezelStyle = .rounded
        accessibilityBtn.target = self
        accessibilityBtn.action = #selector(promptAccessibility)
        view.addSubview(accessibilityBtn)

        let folderLabel = NSTextField(labelWithString: L("onboarding.setup.folder.label"))
        folderLabel.frame = NSRect(x: 0, y: view.bounds.height - 116, width: view.bounds.width, height: 18)
        folderLabel.font = .boldSystemFont(ofSize: 13)
        view.addSubview(folderLabel)

        let chooseBtn = NSButton(frame: NSRect(x: view.bounds.width - 96, y: view.bounds.height - 145, width: 96, height: 26))
        chooseBtn.title = L("prefs.choose")
        chooseBtn.bezelStyle = .rounded
        chooseBtn.target = self
        chooseBtn.action = #selector(chooseFolder)
        view.addSubview(chooseBtn)

        folderField = NSTextField(frame: NSRect(x: 0, y: view.bounds.height - 145, width: view.bounds.width - 106, height: 24))
        folderField.stringValue = currentTaskDirectoryPath()
        folderField.bezelStyle = .roundedBezel
        folderField.focusRingType = .none
        folderField.font = .systemFont(ofSize: 12)
        view.addSubview(folderField)

        let folderHint = NSTextField(wrappingLabelWithString: LF("onboarding.setup.folder.hint", kDefaultTaskFileName))
        folderHint.frame = NSRect(x: 0, y: view.bounds.height - 187, width: view.bounds.width, height: 34)
        folderHint.font = .systemFont(ofSize: 12)
        folderHint.textColor = .secondaryLabelColor
        view.addSubview(folderHint)
    }

    private func buildAIView(in view: NSView) {
        let body = NSTextField(wrappingLabelWithString: L("onboarding.ai.body"))
        body.frame = NSRect(x: 0, y: view.bounds.height - 48, width: view.bounds.width, height: 42)
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        view.addSubview(body)

        let labelW: CGFloat = 120
        let formX: CGFloat = labelW + 8
        let rowProvider = view.bounds.height - 92
        let rowModel = rowProvider - 42
        let rowKey = rowModel - 42

        let providerLabel = NSTextField(labelWithString: L("onboarding.ai.provider"))
        providerLabel.frame = NSRect(x: 0, y: rowProvider + 3, width: labelW, height: 20)
        providerLabel.alignment = .right
        providerLabel.font = .systemFont(ofSize: 13)
        view.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: NSRect(x: formX, y: rowProvider, width: 180, height: 26), pullsDown: false)
        providerPopup.addItems(withTitles: AIProvider.allCases.map { $0.displayName })
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        view.addSubview(providerPopup)

        let modelLabel = NSTextField(labelWithString: L("onboarding.ai.model"))
        modelLabel.frame = NSRect(x: 0, y: rowModel + 3, width: labelW, height: 20)
        modelLabel.alignment = .right
        modelLabel.font = .systemFont(ofSize: 13)
        view.addSubview(modelLabel)

        modelField = NSTextField(frame: NSRect(x: formX, y: rowModel + 1, width: view.bounds.width - formX, height: 24))
        modelField.bezelStyle = .roundedBezel
        modelField.focusRingType = .none
        modelField.font = .systemFont(ofSize: 12)
        view.addSubview(modelField)

        let keyLabel = NSTextField(labelWithString: L("onboarding.ai.apiKey"))
        keyLabel.frame = NSRect(x: 0, y: rowKey + 3, width: labelW, height: 20)
        keyLabel.alignment = .right
        keyLabel.font = .systemFont(ofSize: 13)
        view.addSubview(keyLabel)

        let pasteBtnW: CGFloat = 72
        let pasteBtn = NSButton(frame: NSRect(x: view.bounds.width - pasteBtnW, y: rowKey, width: pasteBtnW, height: 26))
        pasteBtn.title = L("prefs.paste")
        pasteBtn.bezelStyle = .rounded
        pasteBtn.target = self
        pasteBtn.action = #selector(pasteAPIKey)
        view.addSubview(pasteBtn)

        apiKeyField = NSSecureTextField(frame: NSRect(x: formX, y: rowKey + 1, width: view.bounds.width - formX - pasteBtnW - 8, height: 24))
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.focusRingType = .none
        apiKeyField.placeholderString = L("prefs.apiKey.placeholder")
        view.addSubview(apiKeyField)
    }

    private func renderStep() {
        progressLabel.stringValue = LF("onboarding.progress", step.rawValue + 1, totalSteps)

        welcomeView.isHidden = step != .welcome
        setupView.isHidden = step != .setup
        aiView.isHidden = step != .ai

        switch step {
        case .welcome:
            titleLabel.stringValue = L("onboarding.welcome.title")
            subtitleLabel.stringValue = L("onboarding.welcome.subtitle")
            backButton.isHidden = true
            backButton.title = L("onboarding.back")
            primaryButton.title = L("onboarding.start")
        case .setup:
            titleLabel.stringValue = L("onboarding.setup.title")
            subtitleLabel.stringValue = L("onboarding.setup.subtitle")
            backButton.isHidden = false
            backButton.title = L("onboarding.back")
            primaryButton.title = L("onboarding.next")
            updateAccessibilityStatus()
        case .ai:
            titleLabel.stringValue = L("onboarding.ai.title")
            subtitleLabel.stringValue = L("onboarding.ai.subtitle")
            backButton.isHidden = false
            backButton.title = L("onboarding.back")
            primaryButton.title = L("onboarding.finish")
            loadProviderSettings(currentProvider())
        }
    }

    private func currentProvider() -> AIProvider {
        let selected = providerPopup.selectedItem?.title ?? AIProvider.google.displayName
        return AIProvider.allCases.first(where: { $0.displayName == selected }) ?? .google
    }

    private func loadProviderSettings(_ provider: AIProvider) {
        modelField.stringValue = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.modelDefault
        apiKeyField.stringValue = KeychainStore.read(account: provider.keychainAccount) ?? ""
    }

    private func updateAccessibilityStatus() {
        let granted = (NSApp.delegate as? AppDelegate)?.accessibilityGranted() ?? isAccessibilityTrusted()
        accessibilityStatusLabel.stringValue = granted
            ? L("onboarding.setup.accessibility.granted")
            : L("onboarding.setup.accessibility.required")
    }

    private func showValidation(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("onboarding.validation.title")
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func backTapped() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        renderStep()
    }

    @objc private func primaryTapped() {
        switch step {
        case .welcome:
            step = .setup
            renderStep()
        case .setup:
            guard (NSApp.delegate as? AppDelegate)?.accessibilityGranted() ?? isAccessibilityTrusted() else {
                showValidation(message: L("onboarding.validation.accessibility"))
                return
            }
            switch validatedTaskFilePath(forDirectory: folderField.stringValue) {
            case .success(let filePath):
                UserDefaults.standard.set(filePath, forKey: kTaskFilePathDefaultsKey)
            case .failure(let taskError):
                presentTaskPathErrorAlert(window: window, error: taskError)
                return
            }
            step = .ai
            renderStep()
        case .ai:
            let provider = currentProvider()
            UserDefaults.standard.set(provider.rawValue, forKey: kAIProviderDefaultsKey)
            let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(model.isEmpty ? provider.modelDefault : model, forKey: provider.modelDefaultsKey)
            let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                KeychainStore.upsert(account: provider.keychainAccount, value: apiKey)
            }
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.onboardingDidComplete()
            } else {
                UserDefaults.standard.set(true, forKey: kOnboardingCompletedDefaultsKey)
                close()
            }
        }
    }

    @objc private func promptAccessibility() {
        (NSApp.delegate as? AppDelegate)?.promptAccessibility() ?? promptAccessibilityTrustDialog()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateAccessibilityStatus()
        }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L("prefs.openPanel.title")
        panel.message = L("prefs.openPanel.message")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folderField.stringValue)
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            self?.folderField.stringValue = path
        }
    }

    @objc private func providerChanged() {
        loadProviderSettings(currentProvider())
    }

    @objc private func pasteAPIKey() {
        if let text = NSPasteboard.general.string(forType: .string) {
            apiKeyField.stringValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
            window?.makeFirstResponder(apiKeyField)
        }
    }
}

// MARK: - PreferencesWindowController
enum PreferencesPane: Int, CaseIterable {
    case general
    case ai
    case license
    case rewind

    var titleKey: String {
        switch self {
        case .general: return "prefs.sidebar.general"
        case .ai: return "prefs.sidebar.ai"
        case .license: return "prefs.sidebar.license"
        case .rewind: return "prefs.sidebar.rewind"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .ai: return "sparkles"
        case .license: return "key"
        case .rewind: return "clock.arrow.circlepath"
        }
    }
}

final class PreferencesWindowController: NSWindowController {
    private var pathField: NSTextField!
    private var languagePopup: NSPopUpButton!
    private var openAtLoginCheckbox: NSButton!
    private var providerPopup: NSPopUpButton!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var licenseEmailField: NSTextField!
    private var licenseKeyField: NSTextField!
    private var licenseStatusLabel: NSTextField!
    private var activateLicenseButton: NSButton!
    private var refreshLicenseButton: NSButton!
    private var openProButton: NSButton!
    private var rewindEnabledCheckbox: NSButton!
    private var rewindTimePicker: NSDatePicker!
    private var paneTitleLabel: NSTextField!
    private var paneContainer: NSView!
    private var sidebarButtons: [PreferencesPane: NSButton] = [:]
    private var paneViews: [PreferencesPane: NSView] = [:]
    private var selectedPane: PreferencesPane = .general

    convenience init(selectedPane: PreferencesPane = .general) {
        let W: CGFloat = 760
        let H: CGFloat = 540
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("prefs.window.title")
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
        self.selectedPane = selectedPane
        buildUI(W: W, H: H)
        selectPane(selectedPane, makeFirstResponder: false)
    }

    private func buildUI(W: CGFloat, H: CGFloat) {
        guard let cv = window?.contentView else { return }

        let sidebarWidth: CGFloat = 190
        let footerHeight: CGFloat = 56
        let contentX = sidebarWidth + 1
        let contentWidth = W - contentX
        let contentHeight = H - footerHeight
        let contentPad: CGFloat = 24

        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: H))
        sidebar.material = .sidebar
        sidebar.state = .active
        sidebar.blendingMode = .withinWindow
        cv.addSubview(sidebar)

        let verticalSeparator = NSBox(frame: NSRect(x: sidebarWidth, y: 0, width: 1, height: H))
        verticalSeparator.boxType = .separator
        cv.addSubview(verticalSeparator)

        let footerSeparator = NSBox(frame: NSRect(x: 0, y: footerHeight, width: W, height: 1))
        footerSeparator.boxType = .separator
        cv.addSubview(footerSeparator)

        buildSidebar(in: sidebar, width: sidebarWidth, height: H)

        paneTitleLabel = NSTextField(labelWithString: "")
        paneTitleLabel.frame = NSRect(x: contentX + contentPad, y: H - 58, width: contentWidth - contentPad * 2, height: 34)
        paneTitleLabel.font = .boldSystemFont(ofSize: 28)
        cv.addSubview(paneTitleLabel)

        paneContainer = NSView(frame: NSRect(
            x: contentX + contentPad,
            y: footerHeight + 20,
            width: contentWidth - contentPad * 2,
            height: contentHeight - 88
        ))
        cv.addSubview(paneContainer)

        for pane in PreferencesPane.allCases {
            let paneView: NSView
            switch pane {
            case .general:
                paneView = buildGeneralPane(frame: paneContainer.bounds)
            case .ai:
                paneView = buildAIPane(frame: paneContainer.bounds)
            case .license:
                paneView = buildLicensePane(frame: paneContainer.bounds)
            case .rewind:
                paneView = buildRewindPane(frame: paneContainer.bounds)
            }

            paneView.autoresizingMask = [.width, .height]
            paneView.isHidden = true
            paneContainer.addSubview(paneView)
            paneViews[pane] = paneView
        }

        let cancelBtn = NSButton(frame: NSRect(x: W - 16 - 90 - 8 - 80, y: 14, width: 80, height: 28))
        cancelBtn.title = L("common.cancel")
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelPrefs)
        cv.addSubview(cancelBtn)

        let saveBtn = NSButton(frame: NSRect(x: W - 16 - 90, y: 14, width: 90, height: 28))
        saveBtn.title = L("common.save")
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.target = self
        saveBtn.action = #selector(savePrefs)
        cv.addSubview(saveBtn)

        let versionLabel = NSTextField(labelWithString: LF("app.version", appVersionDisplay()))
        versionLabel.frame = NSRect(x: 16, y: 18, width: sidebarWidth - 32, height: 16)
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        sidebar.addSubview(versionLabel)

        loadProviderSettings(currentProvider())
        refreshLicenseSummary()
        window?.initialFirstResponder = firstResponder(for: selectedPane)
    }

    private func buildSidebar(in sidebar: NSView, width: CGFloat, height: CGFloat) {
        let titleLabel = NSTextField(labelWithString: L("prefs.window.title"))
        titleLabel.frame = NSRect(x: 16, y: height - 42, width: width - 32, height: 22)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        sidebar.addSubview(titleLabel)

        let startY = height - 92
        let buttonHeight: CGFloat = 38
        let spacing: CGFloat = 10

        for pane in PreferencesPane.allCases {
            let index = CGFloat(pane.rawValue)
            let button = NSButton(frame: NSRect(
                x: 12,
                y: startY - index * (buttonHeight + spacing),
                width: width - 24,
                height: buttonHeight
            ))
            button.title = L(pane.titleKey)
            button.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: L(pane.titleKey))
            button.imagePosition = .imageLeading
            button.isBordered = false
            button.target = self
            button.action = #selector(sidebarPaneSelected(_:))
            button.tag = pane.rawValue
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            sidebar.addSubview(button)
            sidebarButtons[pane] = button
        }
    }

    private func buildGeneralPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        let labelWidth: CGFloat = 120
        let fieldX: CGFloat = labelWidth + 12
        let rowPath: CGFloat = frame.height - 62
        let rowHint: CGFloat = rowPath - 24
        let rowLanguage: CGFloat = rowHint - 44
        let rowOpenAtLogin: CGFloat = rowLanguage - 52
        let contentWidth = frame.width

        let label = makeFormLabel(L("prefs.taskFile.label"), y: rowPath + 3, width: labelWidth)
        pane.addSubview(label)

        let browseBtn = NSButton(frame: NSRect(x: contentWidth - 90, y: rowPath, width: 90, height: 28))
        browseBtn.title = L("prefs.choose")
        browseBtn.bezelStyle = .rounded
        browseBtn.target = self
        browseBtn.action = #selector(choosePath)
        pane.addSubview(browseBtn)

        pathField = NSTextField(frame: NSRect(
            x: fieldX,
            y: rowPath + 1,
            width: browseBtn.frame.minX - fieldX - 8,
            height: 24
        ))
        pathField.stringValue = currentTaskDirectoryPath()
        pathField.bezelStyle = .roundedBezel
        pathField.focusRingType = .none
        pathField.font = .systemFont(ofSize: 11.5)
        pane.addSubview(pathField)

        let hint = makeHintLabel(L("prefs.taskFile.hint"), frame: NSRect(x: fieldX, y: rowHint, width: contentWidth - fieldX, height: 16))
        pane.addSubview(hint)

        let languageLabel = makeFormLabel(L("prefs.language.label"), y: rowLanguage + 3, width: labelWidth)
        pane.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: rowLanguage, width: 200, height: 28), pullsDown: false)
        let languages = AppLanguage.allCases
        languagePopup.addItems(withTitles: languages.map { $0.displayName })
        let currentLanguage = AppLanguage.current()
        if let idx = languages.firstIndex(of: currentLanguage) {
            languagePopup.selectItem(at: idx)
        }
        pane.addSubview(languagePopup)

        openAtLoginCheckbox = NSButton(checkboxWithTitle: L("prefs.openAtLogin.label"), target: nil, action: nil)
        openAtLoginCheckbox.frame = NSRect(x: fieldX, y: rowOpenAtLogin, width: contentWidth - fieldX, height: 20)
        openAtLoginCheckbox.state = UserDefaults.standard.bool(forKey: kOpenAtLoginDefaultsKey) ? .on : .off
        pane.addSubview(openAtLoginCheckbox)

        return pane
    }

    private func buildAIPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        let labelWidth: CGFloat = 120
        let fieldX: CGFloat = labelWidth + 12
        let contentWidth = frame.width
        let rowProvider: CGFloat = frame.height - 62
        let rowModel: CGFloat = rowProvider - 42
        let rowKey: CGFloat = rowModel - 54

        let providerLabel = makeFormLabel(L("prefs.provider.label"), y: rowProvider + 3, width: labelWidth)
        pane.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: rowProvider, width: 220, height: 28), pullsDown: false)
        providerPopup.addItems(withTitles: AIProvider.allCases.map { $0.displayName })
        let selectedRaw = UserDefaults.standard.string(forKey: kAIProviderDefaultsKey) ?? AIProvider.google.rawValue
        let selectedProvider = AIProvider(rawValue: selectedRaw) ?? .google
        providerPopup.selectItem(withTitle: selectedProvider.displayName)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        pane.addSubview(providerPopup)

        let modelLabel = makeFormLabel(L("prefs.model.label"), y: rowModel + 3, width: labelWidth)
        pane.addSubview(modelLabel)

        modelField = NSTextField(frame: NSRect(x: fieldX, y: rowModel + 1, width: contentWidth - fieldX, height: 24))
        modelField.bezelStyle = .roundedBezel
        modelField.focusRingType = .none
        modelField.font = .systemFont(ofSize: 12)
        pane.addSubview(modelField)

        let keyLabel = makeFormLabel(L("prefs.apiKey.label"), y: rowKey + 3, width: labelWidth)
        pane.addSubview(keyLabel)

        let pasteButtonWidth: CGFloat = 72
        let pasteBtn = NSButton(frame: NSRect(x: contentWidth - pasteButtonWidth, y: rowKey, width: pasteButtonWidth, height: 28))
        pasteBtn.title = L("prefs.paste")
        pasteBtn.bezelStyle = .rounded
        pasteBtn.target = self
        pasteBtn.action = #selector(pasteAPIKey)
        pane.addSubview(pasteBtn)

        apiKeyField = NSSecureTextField(frame: NSRect(
            x: fieldX,
            y: rowKey + 1,
            width: pasteBtn.frame.minX - fieldX - 8,
            height: 24
        ))
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.focusRingType = .none
        apiKeyField.isEditable = true
        apiKeyField.isSelectable = true
        apiKeyField.placeholderString = L("prefs.apiKey.placeholder")
        pane.addSubview(apiKeyField)

        let keyHint = makeHintLabel(L("prefs.apiKey.hint"), frame: NSRect(x: fieldX, y: rowKey - 18, width: contentWidth - fieldX, height: 16))
        pane.addSubview(keyHint)

        return pane
    }

    private func buildLicensePane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        let labelWidth: CGFloat = 120
        let fieldX: CGFloat = labelWidth + 12
        let contentWidth = frame.width
        let rowEmail: CGFloat = frame.height - 62
        let rowKey: CGFloat = rowEmail - 42
        let rowActions: CGFloat = rowKey - 50
        let rowStatus: CGFloat = rowActions - 28

        let licenseEmailLabel = makeFormLabel(L("prefs.license.email"), y: rowEmail + 3, width: labelWidth)
        pane.addSubview(licenseEmailLabel)

        licenseEmailField = NSTextField(frame: NSRect(x: fieldX, y: rowEmail + 1, width: contentWidth - fieldX, height: 24))
        licenseEmailField.stringValue = LicenseManager.licenseEmail()
        licenseEmailField.bezelStyle = .roundedBezel
        licenseEmailField.focusRingType = .none
        licenseEmailField.font = .systemFont(ofSize: 12)
        licenseEmailField.placeholderString = "you@example.com"
        pane.addSubview(licenseEmailField)

        let licenseKeyLabel = makeFormLabel(L("prefs.license.key"), y: rowKey + 3, width: labelWidth)
        pane.addSubview(licenseKeyLabel)

        licenseKeyField = NSTextField(frame: NSRect(x: fieldX, y: rowKey + 1, width: contentWidth - fieldX, height: 24))
        licenseKeyField.stringValue = LicenseManager.savedLicenseKey()
        licenseKeyField.bezelStyle = .roundedBezel
        licenseKeyField.focusRingType = .none
        licenseKeyField.font = .systemFont(ofSize: 12)
        licenseKeyField.placeholderString = "stash_XXXX-XXXX-XXXX-XXXX"
        pane.addSubview(licenseKeyField)

        activateLicenseButton = NSButton(frame: NSRect(x: fieldX, y: rowActions, width: 90, height: 28))
        activateLicenseButton.title = L("prefs.license.activate")
        activateLicenseButton.bezelStyle = .rounded
        activateLicenseButton.target = self
        activateLicenseButton.action = #selector(activateLicense)
        pane.addSubview(activateLicenseButton)

        refreshLicenseButton = NSButton(frame: NSRect(x: fieldX + 98, y: rowActions, width: 90, height: 28))
        refreshLicenseButton.title = L("prefs.license.refresh")
        refreshLicenseButton.bezelStyle = .rounded
        refreshLicenseButton.target = self
        refreshLicenseButton.action = #selector(refreshLicense)
        pane.addSubview(refreshLicenseButton)

        openProButton = NSButton(frame: NSRect(x: fieldX + 196, y: rowActions, width: 160, height: 28))
        openProButton.title = L("prefs.license.openPro")
        openProButton.bezelStyle = .rounded
        openProButton.target = self
        openProButton.action = #selector(openStashPro)
        pane.addSubview(openProButton)

        licenseStatusLabel = NSTextField(labelWithString: LicenseManager.statusSummary())
        licenseStatusLabel.frame = NSRect(x: fieldX, y: rowStatus, width: contentWidth - fieldX, height: 18)
        licenseStatusLabel.font = .systemFont(ofSize: 11)
        licenseStatusLabel.textColor = .secondaryLabelColor
        pane.addSubview(licenseStatusLabel)

        return pane
    }

    private func buildRewindPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        let labelWidth: CGFloat = 120
        let fieldX: CGFloat = labelWidth + 12
        let contentWidth = frame.width
        let rowEnabled: CGFloat = frame.height - 62
        let rowTime: CGFloat = rowEnabled - 46

        rewindEnabledCheckbox = NSButton(
            checkboxWithTitle: L("prefs.rewind.enabledCheckbox"),
            target: nil,
            action: nil
        )
        rewindEnabledCheckbox.frame = NSRect(x: fieldX, y: rowEnabled, width: contentWidth - fieldX, height: 20)
        rewindEnabledCheckbox.state = UserDefaults.standard.bool(forKey: kRewindEnabledKey) ? .on : .off
        pane.addSubview(rewindEnabledCheckbox)

        let rewindTimeLabel = makeFormLabel(L("prefs.rewind.timeLabel"), y: rowTime + 3, width: labelWidth)
        pane.addSubview(rewindTimeLabel)

        rewindTimePicker = NSDatePicker()
        rewindTimePicker.frame = NSRect(x: fieldX, y: rowTime, width: 120, height: 28)
        rewindTimePicker.datePickerStyle = .textFieldAndStepper
        rewindTimePicker.datePickerElements = .hourMinute
        rewindTimePicker.locale = Locale(identifier: "en_US_POSIX")
        rewindTimePicker.isBezeled = true
        let savedHour = UserDefaults.standard.object(forKey: kRewindHourKey) != nil
            ? UserDefaults.standard.integer(forKey: kRewindHourKey)
            : kRewindDefaultHour
        let savedMinute = UserDefaults.standard.object(forKey: kRewindMinuteKey) != nil
            ? UserDefaults.standard.integer(forKey: kRewindMinuteKey)
            : kRewindDefaultMinute
        var comps = DateComponents()
        comps.hour = savedHour
        comps.minute = savedMinute
        rewindTimePicker.dateValue = Calendar.current.date(from: comps) ?? Date()
        pane.addSubview(rewindTimePicker)

        let rewindNote = makeHintLabel(
            L("prefs.rewind.weekdaysNote"),
            frame: NSRect(x: fieldX, y: rowTime - 18, width: contentWidth - fieldX, height: 16)
        )
        pane.addSubview(rewindNote)

        return pane
    }

    private func makeFormLabel(_ text: String, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: width, height: 20)
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func makeHintLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func updateSidebarSelection() {
        for pane in PreferencesPane.allCases {
            guard let button = sidebarButtons[pane] else { continue }
            let isSelected = pane == selectedPane
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            button.attributedTitle = NSAttributedString(
                string: "  " + L(pane.titleKey),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: isSelected ? .semibold : .medium),
                    .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.labelColor,
                    .paragraphStyle: style,
                ]
            )
            button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func firstResponder(for pane: PreferencesPane) -> NSView? {
        switch pane {
        case .general:
            return pathField
        case .ai:
            return modelField
        case .license:
            return licenseEmailField
        case .rewind:
            return rewindEnabledCheckbox
        }
    }

    func selectPane(_ pane: PreferencesPane, makeFirstResponder: Bool = true) {
        selectedPane = pane
        paneTitleLabel?.stringValue = L(pane.titleKey)

        for candidate in PreferencesPane.allCases {
            paneViews[candidate]?.isHidden = candidate != pane
        }

        updateSidebarSelection()

        guard makeFirstResponder, let responder = firstResponder(for: pane) else { return }
        window?.initialFirstResponder = responder
        if window?.isVisible == true {
            window?.makeFirstResponder(responder)
        }
    }

    @objc private func sidebarPaneSelected(_ sender: NSButton) {
        guard let pane = PreferencesPane(rawValue: sender.tag) else { return }
        selectPane(pane)
    }

    @objc private func providerChanged() {
        loadProviderSettings(currentProvider())
    }

    private func currentProvider() -> AIProvider {
        let title = providerPopup.selectedItem?.title ?? AIProvider.google.displayName
        return AIProvider.allCases.first(where: { $0.displayName == title }) ?? .google
    }

    private func loadProviderSettings(_ provider: AIProvider) {
        modelField.stringValue = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.modelDefault
        apiKeyField.stringValue = KeychainStore.read(account: provider.keychainAccount) ?? ""
    }

    private func currentLanguage() -> AppLanguage {
        let selected = languagePopup.indexOfSelectedItem
        guard selected >= 0, selected < AppLanguage.allCases.count else { return .system }
        return AppLanguage.allCases[selected]
    }

    private func setLicenseControlsEnabled(_ enabled: Bool) {
        activateLicenseButton.isEnabled = enabled
        refreshLicenseButton.isEnabled = enabled
        openProButton.isEnabled = enabled
    }

    private func setLicenseStatus(_ message: String, isError: Bool = false) {
        licenseStatusLabel.stringValue = message
        licenseStatusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func refreshLicenseSummary() {
        setLicenseStatus(LicenseManager.statusSummary())
    }

    private func currentLicenseEmail() -> String {
        licenseEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentLicenseKey() -> String {
        licenseKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func message(for error: LicenseServiceError) -> String {
        switch error {
        case .invalidEmail:
            return L("license.error.invalidEmail")
        case .missingCredentials:
            return L("license.error.missingCredentials")
        case .invalidConfiguration:
            return L("license.error.invalidConfiguration")
        case .invalidEntitlement:
            return L("license.error.invalidEntitlement")
        case .invalidResponse:
            return L("license.error.invalidResponse")
        case .unsupportedPlatform:
            return L("license.error.unsupportedPlatform")
        case .transport(let message):
            return LF("license.error.transport", message)
        case .api(_, let message):
            return message
        }
    }

    @objc private func choosePath() {
        let panel = NSOpenPanel()
        panel.title                   = L("prefs.openPanel.title")
        panel.message                 = L("prefs.openPanel.message")
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories    = true
        panel.directoryURL = URL(fileURLWithPath: pathField.stringValue)
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.pathField.stringValue = url.path
            }
        }
    }

    @objc private func pasteAPIKey() {
        if let text = NSPasteboard.general.string(forType: .string) {
            apiKeyField.stringValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
            window?.makeFirstResponder(apiKeyField)
        }
    }

    @objc private func activateLicense() {
        let email = currentLicenseEmail()
        let licenseKey = currentLicenseKey()
        setLicenseControlsEnabled(false)
        setLicenseStatus(L("prefs.license.activating"))

        LicenseManager.activate(email: email, licenseKey: licenseKey) { [weak self] result in
            guard let self else { return }
            self.setLicenseControlsEnabled(true)
            switch result {
            case .success:
                self.refreshLicenseSummary()
            case .failure(let error):
                self.setLicenseStatus(self.message(for: error), isError: true)
            }
        }
    }

    @objc private func refreshLicense() {
        let email = currentLicenseEmail()
        let licenseKey = currentLicenseKey()
        setLicenseControlsEnabled(false)
        setLicenseStatus(L("prefs.license.refreshing"))

        LicenseManager.refresh(email: email, licenseKey: licenseKey) { [weak self] result in
            guard let self else { return }
            self.setLicenseControlsEnabled(true)
            switch result {
            case .success:
                self.refreshLicenseSummary()
            case .failure(let error):
                self.setLicenseStatus(self.message(for: error), isError: true)
            }
        }
    }

    @objc private func openStashPro() {
        LicenseManager.openUpgradePage()
    }

    @objc private func savePrefs() {
        let selectedDirectory = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch validatedTaskFilePath(forDirectory: selectedDirectory) {
        case .success(let resolvedPath):
            UserDefaults.standard.set(resolvedPath, forKey: kTaskFilePathDefaultsKey)
        case .failure(let taskError):
            presentTaskPathErrorAlert(window: window, error: taskError)
            return
        }

        let openAtLogin = openAtLoginCheckbox.state == .on

        let provider = currentProvider()
        UserDefaults.standard.set(provider.rawValue, forKey: kAIProviderDefaultsKey)
        UserDefaults.standard.set(currentLicenseEmail(), forKey: kLicenseEmailDefaultsKey)

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(model.isEmpty ? provider.modelDefault : model, forKey: provider.modelDefaultsKey)

        Localizer.setLanguage(currentLanguage())

        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            KeychainStore.upsert(account: provider.keychainAccount, value: apiKey)
        }

        if #available(macOS 13.0, *) {
            do {
                if openAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.set(openAtLogin, forKey: kOpenAtLoginDefaultsKey)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L("prefs.openAtLogin.error.title")
                alert.informativeText = L("prefs.openAtLogin.error.message")
                alert.runModal()
                return
            }
        } else {
            UserDefaults.standard.set(false, forKey: kOpenAtLoginDefaultsKey)
        }

        // Rewind the Day notification
        let rewindEnabled = rewindEnabledCheckbox.state == .on
        let pickerCal = Calendar.current
        let pickerHour   = pickerCal.component(.hour,   from: rewindTimePicker.dateValue)
        let pickerMinute = pickerCal.component(.minute, from: rewindTimePicker.dateValue)
        UserDefaults.standard.set(rewindEnabled, forKey: kRewindEnabledKey)
        UserDefaults.standard.set(pickerHour,    forKey: kRewindHourKey)
        UserDefaults.standard.set(pickerMinute,  forKey: kRewindMinuteKey)
        if rewindEnabled {
            RewindScheduler.requestAuthIfNeeded { granted in
                guard granted else { return }
                RewindScheduler.schedule(hour: pickerHour, minute: pickerMinute)
            }
        } else {
            RewindScheduler.cancel()
        }

        close()
    }

    @objc private func cancelPrefs() {
        close()
    }
}

// MARK: - HelpWindowController
final class HelpWindowController: NSWindowController {
    convenience init() {
        let W: CGFloat = 460
        let H: CGFloat = 290
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("help.window.title")
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
        buildUI(W: W, H: H)
    }

    private func buildUI(W: CGFloat, H: CGFloat) {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 16

        let title = NSTextField(labelWithString: L("help.title"))
        title.frame = NSRect(x: pad, y: H - 44, width: W - pad * 2, height: 22)
        title.font = .boldSystemFont(ofSize: 16)
        cv.addSubview(title)

        let line1 = NSTextField(labelWithString: L("help.globalHotkey"))
        line1.frame = NSRect(x: pad, y: H - 74, width: W - pad * 2, height: 18)
        line1.font = .systemFont(ofSize: 13)
        cv.addSubview(line1)

        let line2 = NSTextField(labelWithString: L("help.typeShortcuts"))
        line2.frame = NSRect(x: pad, y: H - 100, width: W - pad * 2, height: 18)
        line2.font = .systemFont(ofSize: 13)
        cv.addSubview(line2)

        let line3 = NSTextField(labelWithString: L("help.taskShortcut"))
        line3.frame = NSRect(x: pad + 16, y: H - 124, width: W - pad * 2 - 16, height: 16)
        line3.font = .systemFont(ofSize: 12)
        line3.textColor = .secondaryLabelColor
        cv.addSubview(line3)

        let line4 = NSTextField(labelWithString: L("help.questionShortcut"))
        line4.frame = NSRect(x: pad + 16, y: H - 144, width: W - pad * 2 - 16, height: 16)
        line4.font = .systemFont(ofSize: 12)
        line4.textColor = .secondaryLabelColor
        cv.addSubview(line4)

        let line5 = NSTextField(labelWithString: L("help.goalShortcut"))
        line5.frame = NSRect(x: pad + 16, y: H - 164, width: W - pad * 2 - 16, height: 16)
        line5.font = .systemFont(ofSize: 12)
        line5.textColor = .secondaryLabelColor
        cv.addSubview(line5)

        let line6 = NSTextField(labelWithString: L("help.reminderShortcut"))
        line6.frame = NSRect(x: pad + 16, y: H - 184, width: W - pad * 2 - 16, height: 16)
        line6.font = .systemFont(ofSize: 12)
        line6.textColor = .secondaryLabelColor
        cv.addSubview(line6)

        let line7 = NSTextField(labelWithString: L("help.saveCancel"))
        line7.frame = NSRect(x: pad, y: H - 210, width: W - pad * 2, height: 16)
        line7.font = .systemFont(ofSize: 12)
        line7.textColor = .secondaryLabelColor
        cv.addSubview(line7)

        let versionLabel = NSTextField(labelWithString: LF("app.version", appVersionDisplay()))
        versionLabel.frame = NSRect(x: pad, y: pad + 4, width: 190, height: 16)
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        cv.addSubview(versionLabel)

        let closeBtn = NSButton(frame: NSRect(x: W - pad - 90, y: pad, width: 90, height: 26))
        closeBtn.title = L("common.close")
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.target = self
        closeBtn.action = #selector(closeHelp)
        cv.addSubview(closeBtn)

        let aboutBtn = NSButton(frame: NSRect(x: W - pad - 90 - 8 - 90, y: pad, width: 90, height: 26))
        aboutBtn.title = L("menu.about")
        aboutBtn.bezelStyle = .rounded
        aboutBtn.target = self
        aboutBtn.action = #selector(showAbout)
        cv.addSubview(aboutBtn)
    }

    @objc private func closeHelp() {
        close()
    }

    @objc private func showAbout() {
        (NSApp.delegate as? AppDelegate)?.showAboutPanelProxy()
    }
}

// MARK: - TaskViewController
final class TaskViewController: NSViewController {
    private var textField: NSTextField!
    private var segControl: NSSegmentedControl!
    private var hintLabel: NSTextField!
    private var descriptionLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var loadingIndicator: NSProgressIndicator!
    private var retryButton: NSButton!
    private var helpButton: NSButton!
    private var selectedIcon = kIcons[0].symbol
    private var localKeyMonitor: Any?
    private var languageObserver: NSObjectProtocol?
    private var isSaving = false

    private let vW:  CGFloat = 380
    private let vH:  CGFloat = 148
    private let pad: CGFloat = 12

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: vW, height: vH))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .stashLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLocalizedUI()
        }
    }

    deinit {
        if let observer = languageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func buildUI() {
        let topY: CGFloat = vH - pad - 28

        // Segmented control nativo — seleciona o ícone/prefixo da tarefa
        let labels = kIcons.map { $0.symbol }
        segControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                        target: self, action: #selector(segmentChanged(_:)))
        segControl.selectedSegment = 0
        let segW: CGFloat = CGFloat(kIcons.count) * 50
        let segX: CGFloat = (vW - segW) / 2
        segControl.frame = NSRect(x: segX, y: topY, width: segW, height: 26)
        for i in 0..<kIcons.count {
            segControl.setToolTip(L(kIcons[i].tooltipKey), forSegment: i)
        }
        view.addSubview(segControl)

        // Hint em linha dedicada para evitar truncamento e melhorar leitura
        hintLabel = NSTextField(labelWithString: L("task.hint.shortcuts"))
        hintLabel.frame     = NSRect(x: pad, y: topY - 19, width: vW - pad * 2, height: 16)
        hintLabel.alignment = .center
        hintLabel.font      = .systemFont(ofSize: 10.5)
        hintLabel.textColor = .tertiaryLabelColor
        view.addSubview(hintLabel)

        // Botões de ajuda e sair — canto superior direito
        helpButton = NSButton(frame: NSRect(x: vW - pad - 48, y: topY + 2, width: 22, height: 22))
        helpButton.title = ""
        helpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: L("task.help.accessibility"))
        helpButton.contentTintColor = .tertiaryLabelColor
        helpButton.bezelStyle = .inline
        helpButton.isBordered = false
        helpButton.target = self
        helpButton.action = #selector(openHelp)
        view.addSubview(helpButton)

        let quitBtn = NSButton(frame: NSRect(x: vW - pad - 22, y: topY + 2, width: 22, height: 22))
        quitBtn.title             = ""
        quitBtn.image             = NSImage(systemSymbolName: "xmark.circle.fill",
                                            accessibilityDescription: L("task.quit.accessibility"))
        quitBtn.contentTintColor  = .tertiaryLabelColor
        quitBtn.bezelStyle        = .inline
        quitBtn.isBordered        = false
        quitBtn.target            = self
        quitBtn.action            = #selector(quitApp)
        view.addSubview(quitBtn)

        // Campo de texto — sem anel de foco colorido
        textField = NSTextField(frame: NSRect(x: pad, y: pad + 26, width: vW - pad * 2, height: 40))
        textField.placeholderString = L("task.input.placeholder.default")
        textField.font              = .systemFont(ofSize: 14)
        textField.bezelStyle        = .roundedBezel
        textField.focusRingType     = .none
        textField.delegate          = self
        view.addSubview(textField)

        loadingIndicator = NSProgressIndicator(frame: NSRect(x: pad, y: pad + 4, width: 16, height: 16))
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        view.addSubview(loadingIndicator)

        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.frame = NSRect(x: pad + 22, y: pad + 3, width: vW - pad * 2 - 22, height: 18)
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(descriptionLabel)

        let retryW: CGFloat = 104
        retryButton = NSButton(frame: NSRect(x: vW - pad - retryW, y: pad, width: retryW, height: 22))
        retryButton.title = L("task.retry")
        retryButton.bezelStyle = .rounded
        retryButton.font = .systemFont(ofSize: 11)
        retryButton.target = self
        retryButton.action = #selector(retrySave)
        retryButton.isHidden = true
        view.addSubview(retryButton)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: pad + 22, y: pad + 3, width: vW - pad * 2 - 22 - retryW - 8, height: 18)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reset()
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(self.textField)
        }
        // Monitor local: Cmd+1/2/3 seleciona ícone sem perder foco no campo
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let ch = event.charactersIgnoringModifiers,
                  let digit = Int(ch), digit >= 1, digit <= kIcons.count else { return event }
            self.selectSegment(digit - 1)
            return nil  // consome o evento
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        selectSegment(sender.selectedSegment)
    }

    private func selectSegment(_ index: Int) {
        guard index < kIcons.count else { return }
        selectedIcon = kIcons[index].symbol
        segControl?.selectedSegment = index
        textField?.placeholderString = L(kIcons[index].placeholderKey)
        descriptionLabel?.stringValue = L(kIcons[index].descriptionKey)
    }

    private func refreshLocalizedUI() {
        hintLabel?.stringValue = L("task.hint.shortcuts")
        retryButton?.title = L("task.retry")
        helpButton?.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: L("task.help.accessibility"))
        for i in 0..<kIcons.count {
            segControl?.setToolTip(L(kIcons[i].tooltipKey), forSegment: i)
        }

        let currentIndex = max(segControl.selectedSegment, 0)
        selectSegment(currentIndex)
    }

    @objc private func quitApp() {
        let alert = NSAlert()
        alert.messageText     = L("task.quit.confirm.title")
        alert.informativeText = L("task.quit.confirm.message")
        alert.alertStyle      = .warning
        alert.addButton(withTitle: L("task.quit.confirm.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @objc private func openHelp() {
        (NSApp.delegate as? AppDelegate)?.showHelp()
    }

    private func saveTask() {
        guard !isSaving else { return }
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { dismiss(); return }

        if selectedIcon != "🔔" {
            beginSaving(message: L("status.saving"))
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.writeTask("\(self.selectedIcon) \(text)")
                    self.finishSaving(message: L("status.done"))
                } catch {
                    self.finishError(message: L("status.task.write.error"))
                }
            }
            return
        }

        beginSaving(message: L("status.reminder.parsing"))
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = ReminderAIParser.parse(text)
            let reminderTitle = parsed?.title ?? text
            let hadAIParse = (parsed != nil)
            do {
                try self.writeTask("\(self.selectedIcon) \(reminderTitle)", reminderDate: parsed?.dueDate)
            } catch {
                self.finishError(message: L("status.task.write.error"))
                return
            }
            let saved = self.createReminder(title: reminderTitle, dueDate: parsed?.dueDate)

            if saved {
                if let due = parsed?.dueDate {
                    let fmt = DateFormatter()
                    fmt.dateStyle = .short
                    fmt.timeStyle = .short
                    self.finishSaving(message: LF("status.reminder.created.withDate", fmt.string(from: due)))
                } else if hadAIParse {
                    self.finishSaving(message: L("status.reminder.created"))
                } else {
                    self.finishSaving(message: L("status.reminder.created.noDate"))
                }
            } else {
                self.finishError(message: L("status.reminder.error"))
            }
        }
    }

    @objc private func retrySave() {
        retryButton.isHidden = true
        saveTask()
    }

    private func beginSaving(message: String) {
        DispatchQueue.main.async {
            self.isSaving = true
            self.textField.isEnabled = false
            self.segControl.isEnabled = false
            self.retryButton.isHidden = true
            self.descriptionLabel.isHidden = true
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = .secondaryLabelColor
            self.statusLabel.isHidden = false
            self.loadingIndicator.startAnimation(nil)
        }
    }

    private func finishSaving(message: String) {
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimation(nil)
            self.retryButton.isHidden = true
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = .systemGreen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.dismiss()
                self.isSaving = false
                self.textField.isEnabled = true
                self.segControl.isEnabled = true
                self.descriptionLabel.isHidden = false
            }
        }
    }

    private func finishError(message: String) {
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimation(nil)
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = .systemRed
            self.statusLabel.isHidden = false
            self.retryButton.isHidden = false
            self.isSaving = false
            self.textField.isEnabled = true
            self.segControl.isEnabled = true
            self.descriptionLabel.isHidden = true
            self.view.window?.makeFirstResponder(self.textField)
        }
    }

    private func createReminder(title: String, dueDate: Date?) -> Bool {
        let store = EKEventStore()
        let sem = DispatchSemaphore(value: 0)
        var granted = false

        store.requestFullAccessToReminders { ok, _ in
            granted = ok
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 8)
        guard granted else { return false }

        let calendar = reminderCalendar(in: store)
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: TimeZone.current, from: dueDate)
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func reminderCalendar(in store: EKEventStore) -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == kReminderListName }) {
            return existing
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = kReminderListName
        calendar.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first

        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            return store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first ?? calendar
        }
    }

    private func writeTask(_ task: String, reminderDate: Date? = nil) throws {
        try StashFileParser.appendTaskLine(task, reminderDate: reminderDate, for: Date(), in: taskFilePath)
    }

    private func dismiss() {
        (NSApp.delegate as? AppDelegate)?.popover.performClose(nil)
    }

    private func reset() {
        textField?.stringValue = ""
        descriptionLabel?.isHidden = false
        statusLabel?.isHidden = true
        retryButton?.isHidden = true
        selectSegment(0)
    }
}

// MARK: - NSTextFieldDelegate
extension TaskViewController: NSTextFieldDelegate {
    @objc func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):   saveTask(); return true
        case #selector(NSResponder.cancelOperation(_:)): dismiss();  return true
        default: return false
        }
    }
}

// MARK: - Entry point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // sem ícone no Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
