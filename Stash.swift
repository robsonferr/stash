import Cocoa
import EventKit
import Security
import ServiceManagement

// MARK: - Configuration
private let kDefaultFilePath = "/Users/robsonferreira/Documents/my_tasks.txt"
private var taskFilePath: String {
    UserDefaults.standard.string(forKey: "stash.taskFilePath") ?? kDefaultFilePath
}
private let kReminderListName = "Stash"
private let kAIProviderDefaultsKey = "stash.ai.provider"
private let kLanguageDefaultsKey = "stash.language"
private let kOpenAtLoginDefaultsKey = "stash.openAtLogin"
private let kGeminiModelDefault = "gemini-3-flash-preview"
private let kGeminiModelDefaultsKey = "stash.ai.google.model"
private let kOpenAIModelDefault = "gpt-5.3"
private let kOpenAIModelDefaultsKey = "stash.ai.openai.model"
private let kAnthropicModelDefault = "claude-opus-4-1"
private let kAnthropicModelDefaultsKey = "stash.ai.anthropic.model"
private let kGoogleAPIKeyAccount = "google_api_key"
private let kOpenAIAPIKeyAccount = "openai_api_key"
private let kAnthropicAPIKeyAccount = "anthropic_api_key"
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

private func appShortVersion() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.3.0"
}

private func appBuildVersion() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
}

private func appVersionDisplay() -> String {
    "\(appShortVersion()) (\(appBuildVersion()))"
}

// MARK: - AI + Secrets
private enum KeychainStore {
    static let service = "com.robsonferreira.stash"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func upsert(account: String, value: String) {
        let data = Data(value.utf8)
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
    let lineIndex: Int
    let icon: String
    let text: String
    var isDone: Bool
    var doneDate: Date?
    var reminderDate: Date?
}

private struct DayBlock {
    let date: Date
    var entries: [StashEntry]
}

private enum ReviewPeriod {
    case day(Date)
    case week(start: Date, end: Date)
}

// MARK: - StashFileParser

private enum StashFileParser {

    static func parse(from path: String) -> [DayBlock] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n")
        var blocks: [DayBlock] = []
        var currentDate: Date? = nil
        var currentEntries: [StashEntry] = []

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "dd/MM/yyyy"

        let doneFmt = DateFormatter()
        doneFmt.locale = Locale(identifier: "en_US_POSIX")
        doneFmt.dateFormat = "dd/MM/yyyy"

        let reminderFmt = DateFormatter()
        reminderFmt.locale = Locale(identifier: "en_US_POSIX")
        reminderFmt.dateFormat = "dd/MM/yyyy HH:mm"

        for (idx, line) in lines.enumerated() {
            // Day header: "📅 dd/MM/yyyy"
            if line.hasPrefix("📅 ") {
                if let date = currentDate {
                    blocks.append(DayBlock(date: date, entries: currentEntries))
                }
                // "📅 " = 2 Swift Characters (emoji + space)
                let dateStr = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentDate = dayFmt.date(from: dateStr)
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

            currentEntries.append(StashEntry(
                lineIndex: idx,
                icon: iconStr,
                text: taskText,
                isDone: isDone,
                doneDate: doneDate,
                reminderDate: reminderDate
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
    private var entry: StashEntry
    private let onToggle: (Bool) -> Void

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

    init(entry: StashEntry, width: CGFloat, onToggle: @escaping (Bool) -> Void) {
        self.entry = entry
        self.onToggle = onToggle

        toggleBtn = NSButton()
        iconLabel = NSTextField(labelWithString: entry.icon)
        textLabel = NSTextField(labelWithString: entry.text)

        let h = ReviewRowView.rowHeight(for: entry)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

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
        textLabel.frame = NSRect(x: textX, y: contentY, width: frame.width - textX - pad, height: contentH)
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
                let tagText = L("review.scheduled.tag")
                let tag = NSTextField(labelWithString: tagText)
                tag.font = .systemFont(ofSize: 9, weight: .semibold)
                tag.textColor = .white
                tag.backgroundColor = NSColor.systemOrange
                tag.drawsBackground = true
                tag.isBezeled = false
                tag.sizeToFit()
                let tagW = tag.frame.width + 8
                let tagH: CGFloat = 14
                tag.frame = NSRect(x: frame.width - pad - tagW, y: 5, width: tagW, height: tagH)
                tag.alignment = .center
                tag.wantsLayer = true
                tag.layer?.cornerRadius = 3
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
}

final class ReviewWindowController: NSWindowController {
    private let period: ReviewPeriod
    private var stackView: NSStackView!
    private let W: CGFloat = 500
    private let H: CGFloat = 540

    fileprivate init(period: ReviewPeriod) {
        self.period = period
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
                for entry in block.entries {
                    let rowH = ReviewRowView.rowHeight(for: entry)
                    let row = ReviewRowView(entry: entry, width: W) { _ in }
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

    @objc private func closeWindow() { close() }
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var preferencesWindowController: PreferencesWindowController?
    private var helpWindowController: HelpWindowController?
    private var reviewWindowController: ReviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        requestAccessibilityIfNeeded()
        setupHotkey()
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

    // Solicita permissão de Acessibilidade (necessária para o hotkey global)
    private func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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

    private func openReview(period: ReviewPeriod) {
        if let ctrl = reviewWindowController, ctrl.window?.isVisible == true {
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        reviewWindowController = ReviewWindowController(period: period)
        reviewWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openTaskFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: taskFilePath))
    }

    @objc private func showPreferences() {
        if let ctrl = preferencesWindowController, ctrl.window?.isVisible == true {
            ctrl.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        preferencesWindowController = PreferencesWindowController()
        preferencesWindowController?.showWindow(nil)
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
}

// MARK: - PreferencesWindowController
final class PreferencesWindowController: NSWindowController {
    private var pathField: NSTextField!
    private var languagePopup: NSPopUpButton!
    private var openAtLoginCheckbox: NSButton!
    private var providerPopup: NSPopUpButton!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!

    convenience init() {
        let W: CGFloat = 460
        let H: CGFloat = 352
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
        buildUI(W: W, H: H)
    }

    private func buildUI(W: CGFloat, H: CGFloat) {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 16
        let labelW: CGFloat = 150
        let rowPath: CGFloat = H - 56
        let rowPathHint: CGFloat = rowPath - 22
        let rowLanguage: CGFloat = rowPathHint - 34
        let rowOpenAtLogin: CGFloat = rowLanguage - 36
        let rowProvider: CGFloat = rowOpenAtLogin - 36
        let rowModel: CGFloat = rowProvider - 38
        let rowKey: CGFloat = rowModel - 52

        // Label
        let label = NSTextField(labelWithString: L("prefs.taskFile.label"))
        label.frame     = NSRect(x: pad, y: rowPath + 3, width: labelW, height: 20)
        label.alignment = .right
        label.font      = .systemFont(ofSize: 13)
        cv.addSubview(label)

        // Botão "Escolher..."
        let browseBtn = NSButton(frame: NSRect(x: W - pad - 90, y: rowPath, width: 90, height: 26))
        browseBtn.title      = L("prefs.choose")
        browseBtn.bezelStyle = .rounded
        browseBtn.target     = self
        browseBtn.action     = #selector(choosePath)
        cv.addSubview(browseBtn)

        // Campo de caminho
        let pfX: CGFloat = pad + labelW + 8
        pathField = NSTextField(frame: NSRect(x: pfX, y: rowPath + 1,
                                              width: browseBtn.frame.minX - pfX - 8, height: 24))
        pathField.stringValue   = taskFilePath
        pathField.bezelStyle    = .roundedBezel
        pathField.focusRingType = .none
        pathField.font          = .systemFont(ofSize: 11.5)
        cv.addSubview(pathField)

        // Hint
        let hint = NSTextField(labelWithString: L("prefs.taskFile.hint"))
        hint.frame     = NSRect(x: pad, y: rowPathHint, width: W - pad * 2, height: 16)
        hint.font      = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        cv.addSubview(hint)

        // Idioma do app
        let languageLabel = NSTextField(labelWithString: L("prefs.language.label"))
        languageLabel.frame = NSRect(x: pad, y: rowLanguage + 3, width: labelW, height: 20)
        languageLabel.alignment = .right
        languageLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: pfX, y: rowLanguage, width: 180, height: 26), pullsDown: false)
        let languages = AppLanguage.allCases
        languagePopup.addItems(withTitles: languages.map { $0.displayName })
        let currentLanguage = AppLanguage.current()
        if let idx = languages.firstIndex(of: currentLanguage) {
            languagePopup.selectItem(at: idx)
        }
        cv.addSubview(languagePopup)

        openAtLoginCheckbox = NSButton(checkboxWithTitle: L("prefs.openAtLogin.label"), target: nil, action: nil)
        openAtLoginCheckbox.frame = NSRect(x: pfX, y: rowOpenAtLogin, width: W - pfX - pad, height: 20)
        openAtLoginCheckbox.state = UserDefaults.standard.bool(forKey: kOpenAtLoginDefaultsKey) ? .on : .off
        cv.addSubview(openAtLoginCheckbox)

        // Fornecedor AI
        let providerLabel = NSTextField(labelWithString: L("prefs.provider.label"))
        providerLabel.frame = NSRect(x: pad, y: rowProvider + 3, width: labelW, height: 20)
        providerLabel.alignment = .right
        providerLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: NSRect(x: pfX, y: rowProvider, width: 180, height: 26), pullsDown: false)
        providerPopup.addItems(withTitles: AIProvider.allCases.map { $0.displayName })
        let selectedRaw = UserDefaults.standard.string(forKey: kAIProviderDefaultsKey) ?? AIProvider.google.rawValue
        let selectedProvider = AIProvider(rawValue: selectedRaw) ?? .google
        providerPopup.selectItem(withTitle: selectedProvider.displayName)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        cv.addSubview(providerPopup)

        // Modelo
        let modelLabel = NSTextField(labelWithString: L("prefs.model.label"))
        modelLabel.frame = NSRect(x: pad, y: rowModel + 3, width: labelW, height: 20)
        modelLabel.alignment = .right
        modelLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(modelLabel)

        modelField = NSTextField(frame: NSRect(x: pfX, y: rowModel + 1, width: W - pfX - pad, height: 24))
        modelField.bezelStyle = .roundedBezel
        modelField.focusRingType = .none
        modelField.font = .systemFont(ofSize: 12)
        cv.addSubview(modelField)

        // API key do fornecedor selecionado (Keychain)
        let keyLabel = NSTextField(labelWithString: L("prefs.apiKey.label"))
        keyLabel.frame = NSRect(x: pad, y: rowKey + 3, width: labelW, height: 20)
        keyLabel.alignment = .right
        keyLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(keyLabel)

        let pasteBtnW: CGFloat = 72
        let pasteBtn = NSButton(frame: NSRect(x: W - pad - pasteBtnW, y: rowKey, width: pasteBtnW, height: 26))
        pasteBtn.title = L("prefs.paste")
        pasteBtn.bezelStyle = .rounded
        pasteBtn.target = self
        pasteBtn.action = #selector(pasteAPIKey)
        cv.addSubview(pasteBtn)

        apiKeyField = NSSecureTextField(frame: NSRect(x: pfX, y: rowKey + 1,
                                   width: pasteBtn.frame.minX - pfX - 8, height: 24))
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.focusRingType = .none
        apiKeyField.isEditable = true
        apiKeyField.isSelectable = true
        apiKeyField.placeholderString = L("prefs.apiKey.placeholder")
        cv.addSubview(apiKeyField)

        let keyHint = NSTextField(labelWithString: L("prefs.apiKey.hint"))
        keyHint.frame = NSRect(x: pfX, y: rowKey - 18, width: W - pfX - pad, height: 16)
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = .secondaryLabelColor
        cv.addSubview(keyHint)

        window?.initialFirstResponder = pathField

        // Botão Cancelar
        let cancelBtn = NSButton(frame: NSRect(x: W - pad - 90 - 8 - 80, y: pad, width: 80, height: 26))
        cancelBtn.title      = L("common.cancel")
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target     = self
        cancelBtn.action     = #selector(cancelPrefs)
        cv.addSubview(cancelBtn)

        // Botão Salvar (padrão — responde ao Enter)
        let saveBtn = NSButton(frame: NSRect(x: W - pad - 90, y: pad, width: 90, height: 26))
        saveBtn.title         = L("common.save")
        saveBtn.bezelStyle    = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.target        = self
        saveBtn.action        = #selector(savePrefs)
        cv.addSubview(saveBtn)

        let versionLabel = NSTextField(labelWithString: LF("app.version", appVersionDisplay()))
        versionLabel.frame = NSRect(x: pad, y: pad + 4, width: 200, height: 16)
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        cv.addSubview(versionLabel)

        loadProviderSettings(currentProvider())
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

    @objc private func choosePath() {
        let panel = NSOpenPanel()
        panel.title                   = L("prefs.openPanel.title")
        panel.message                 = L("prefs.openPanel.message")
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories    = true
        panel.directoryURL = URL(fileURLWithPath: pathField.stringValue).deletingLastPathComponent()
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

    @objc private func savePrefs() {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        UserDefaults.standard.set(path, forKey: "stash.taskFilePath")

        let openAtLogin = openAtLoginCheckbox.state == .on

        let provider = currentProvider()
        UserDefaults.standard.set(provider.rawValue, forKey: kAIProviderDefaultsKey)

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
                self.writeTask("\(self.selectedIcon) \(text)")
                self.finishSaving(message: L("status.done"))
            }
            return
        }

        beginSaving(message: L("status.reminder.parsing"))
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = ReminderAIParser.parse(text)
            let reminderTitle = parsed?.title ?? text
            let hadAIParse = (parsed != nil)
            self.writeTask("\(self.selectedIcon) \(reminderTitle)", reminderDate: parsed?.dueDate)
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

    private func writeTask(_ task: String, reminderDate: Date? = nil) {
        var taskLine = task
        if let rd = reminderDate {
            let rdFmt = DateFormatter()
            rdFmt.locale = Locale(identifier: "en_US_POSIX")
            rdFmt.dateFormat = "dd/MM/yyyy HH:mm"
            taskLine += " ⏰ \(rdFmt.string(from: rd))"
        }
        let indented = "    \(taskLine)"
        let url = URL(fileURLWithPath: taskFilePath)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd/MM/yyyy"
        let todayHeader = "📅 \(fmt.string(from: Date()))"

        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        if content.contains(todayHeader) {
            // Insere a linha indentada ao final do bloco de hoje
            var lines = content.components(separatedBy: "\n")
            guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix(todayHeader) }) else { return }
            var insertIdx = headerIdx + 1
            while insertIdx < lines.count {
                let trimmed = lines[insertIdx].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || lines[insertIdx].hasPrefix("📅") { break }
                insertIdx += 1
            }
            lines.insert(indented, at: insertIdx)
            content = lines.joined(separator: "\n")
        } else {
            // Novo dia: adiciona header no topo seguido de linha em branco
            let separator = content.isEmpty ? "" : "\n"
            content = "\(todayHeader)\n\(indented)\n\(separator)\(content)"
        }

        try? content.write(to: url, atomically: true, encoding: .utf8)
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
