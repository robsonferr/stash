import Cocoa
import EventKit
import Security

// MARK: - Configuration
private let kDefaultFilePath = "/Users/robsonferreira/Documents/my_tasks.txt"
private var taskFilePath: String {
    UserDefaults.standard.string(forKey: "stash.taskFilePath") ?? kDefaultFilePath
}
private let kReminderListName = "Stash"
private let kGeminiModelDefault = "gemini-3-flash-preview"
private let kGeminiModelDefaultsKey = "stash.ai.google.model"
private let kGoogleAPIKeyAccount = "google_api_key"
private let kIcons: [(symbol: String, tooltip: String, placeholder: String)] = [
    ("📥", "Guardar para depois  ⌘1", "Guardar uma tarefa..."),
    ("❓", "Dúvida  ⌘2",             "Guardar uma dúvida..."),
    ("🎯", "Objetivo  ⌘3",           "Guardar um objetivo..."),
    ("🔔", "Lembrete  ⌘4",           "Guardar um lembrete..."),
]
// Hotkey: Cmd+Shift+Space  (keyCode 49)
private let kHotkeyMask: NSEvent.ModifierFlags = [.command, .shift]
private let kHotkeyCode: UInt16 = 49

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

private struct ParsedReminder {
    let title: String
    let dueDate: Date?
}

private enum ReminderAIParser {
    static func parse(_ input: String) -> ParsedReminder? {
        guard let key = resolvedAPIKey(), !key.isEmpty else { return nil }

        let model = UserDefaults.standard.string(forKey: kGeminiModelDefaultsKey) ?? kGeminiModelDefault
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
        - language: pt-BR

        User text:
        \(input)
        """

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

        let sem = DispatchSemaphore(value: 0)
        var payload: Data?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            payload = data
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 10)
        guard let response = payload else { return nil }
        return parseGeminiResponse(response, fallbackTitle: input)
    }

    private static func resolvedAPIKey() -> String? {
        if let fromKeychain = KeychainStore.read(account: kGoogleAPIKeyAccount), !fromKeychain.isEmpty {
            return fromKeychain
        }
        if let fromEnv = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !fromEnv.isEmpty {
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

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        requestAccessibilityIfNeeded()
        setupHotkey()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        if let icon = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Stash") {
            icon.isTemplate = true  // adapta automaticamente ao tema claro/escuro
            btn.image = icon
        }
        btn.target = self
        btn.action = #selector(statusButtonClicked(_:))
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            popover.isShown ? popover.performClose(nil) : showPopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let openItem = menu.addItem(
            withTitle: "Abrir arquivo de tarefas",
            action: #selector(openTaskFile),
            keyEquivalent: ""
        )
        openItem.target = self
        let prefsItem = menu.addItem(
            withTitle: "Preferências...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Sair",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        // Padrão canônico: define menu, dispara click (bloqueante até fechar), limpa
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!

    convenience init() {
        let W: CGFloat = 460
        let H: CGFloat = 240
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Preferências — Stash"
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
        buildUI(W: W, H: H)
    }

    private func buildUI(W: CGFloat, H: CGFloat) {
        guard let cv = window?.contentView else { return }
        let pad: CGFloat = 16
        let rowPath: CGFloat = H - 46
        let rowModel: CGFloat = rowPath - 42
        let rowKey: CGFloat = rowModel - 42

        // Label
        let label = NSTextField(labelWithString: "Arquivo de tarefas:")
        label.frame     = NSRect(x: pad, y: rowPath + 3, width: 130, height: 20)
        label.alignment = .right
        label.font      = .systemFont(ofSize: 13)
        cv.addSubview(label)

        // Botão "Escolher..."
        let browseBtn = NSButton(frame: NSRect(x: W - pad - 90, y: rowPath, width: 90, height: 26))
        browseBtn.title      = "Escolher..."
        browseBtn.bezelStyle = .rounded
        browseBtn.target     = self
        browseBtn.action     = #selector(choosePath)
        cv.addSubview(browseBtn)

        // Campo de caminho
        let pfX: CGFloat = pad + 130 + 8
        pathField = NSTextField(frame: NSRect(x: pfX, y: rowPath + 1,
                                              width: browseBtn.frame.minX - pfX - 8, height: 24))
        pathField.stringValue   = taskFilePath
        pathField.bezelStyle    = .roundedBezel
        pathField.focusRingType = .none
        pathField.font          = .systemFont(ofSize: 11.5)
        cv.addSubview(pathField)

        // Hint
        let hint = NSTextField(labelWithString: "O arquivo será criado automaticamente se não existir.")
        hint.frame     = NSRect(x: pad, y: rowPath - 24, width: W - pad * 2, height: 16)
        hint.font      = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        cv.addSubview(hint)

        // Modelo Gemini
        let modelLabel = NSTextField(labelWithString: "Modelo Gemini:")
        modelLabel.frame = NSRect(x: pad, y: rowModel + 3, width: 130, height: 20)
        modelLabel.alignment = .right
        modelLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(modelLabel)

        modelField = NSTextField(frame: NSRect(x: pfX, y: rowModel + 1, width: W - pfX - pad, height: 24))
        modelField.stringValue = UserDefaults.standard.string(forKey: kGeminiModelDefaultsKey) ?? kGeminiModelDefault
        modelField.bezelStyle = .roundedBezel
        modelField.focusRingType = .none
        modelField.font = .systemFont(ofSize: 12)
        cv.addSubview(modelField)

        // API key do Google (Keychain)
        let keyLabel = NSTextField(labelWithString: "Google API key:")
        keyLabel.frame = NSRect(x: pad, y: rowKey + 3, width: 130, height: 20)
        keyLabel.alignment = .right
        keyLabel.font = .systemFont(ofSize: 13)
        cv.addSubview(keyLabel)

        apiKeyField = NSSecureTextField(frame: NSRect(x: pfX, y: rowKey + 1, width: W - pfX - pad, height: 24))
        apiKeyField.stringValue = KeychainStore.read(account: kGoogleAPIKeyAccount) ?? ""
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.focusRingType = .none
        apiKeyField.placeholderString = "Armazenada no Keychain (nao vai para o git)"
        cv.addSubview(apiKeyField)

        let keyHint = NSTextField(labelWithString: "Usado para interpretar texto de lembrete com Gemini.")
        keyHint.frame = NSRect(x: pfX, y: rowKey - 18, width: W - pfX - pad, height: 16)
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = .secondaryLabelColor
        cv.addSubview(keyHint)

        // Botão Cancelar
        let cancelBtn = NSButton(frame: NSRect(x: W - pad - 90 - 8 - 80, y: pad, width: 80, height: 26))
        cancelBtn.title      = "Cancelar"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target     = self
        cancelBtn.action     = #selector(cancelPrefs)
        cv.addSubview(cancelBtn)

        // Botão Salvar (padrão — responde ao Enter)
        let saveBtn = NSButton(frame: NSRect(x: W - pad - 90, y: pad, width: 90, height: 26))
        saveBtn.title         = "Salvar"
        saveBtn.bezelStyle    = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.target        = self
        saveBtn.action        = #selector(savePrefs)
        cv.addSubview(saveBtn)
    }

    @objc private func choosePath() {
        let panel = NSOpenPanel()
        panel.title                   = "Selecionar arquivo de tarefas"
        panel.message                 = "Escolha o arquivo onde as tarefas serão salvas."
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

    @objc private func savePrefs() {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        UserDefaults.standard.set(path, forKey: "stash.taskFilePath")

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(model.isEmpty ? kGeminiModelDefault : model, forKey: kGeminiModelDefaultsKey)

        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            KeychainStore.upsert(account: kGoogleAPIKeyAccount, value: apiKey)
        }
        close()
    }

    @objc private func cancelPrefs() {
        close()
    }
}

// MARK: - TaskViewController
final class TaskViewController: NSViewController {
    private var textField: NSTextField!
    private var segControl: NSSegmentedControl!
    private var selectedIcon = kIcons[0].symbol
    private var localKeyMonitor: Any?

    private let vW:  CGFloat = 380
    private let vH:  CGFloat = 118
    private let pad: CGFloat = 12

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: vW, height: vH))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        let topY: CGFloat = vH - pad - 26   // linha superior

        // Segmented control nativo — seleciona o ícone/prefixo da tarefa
        let labels = kIcons.map { $0.symbol }
        segControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                        target: self, action: #selector(segmentChanged(_:)))
        segControl.selectedSegment = 0
        segControl.frame = NSRect(x: pad, y: topY, width: CGFloat(kIcons.count) * 50, height: 26)
        view.addSubview(segControl)

        // Hint centralizado entre o segmented e o botão quit
        let hintX = pad + CGFloat(kIcons.count) * 50 + 8
        let hint = NSTextField(labelWithString: "↵ salvar  •  Esc cancelar")
        hint.frame     = NSRect(x: hintX, y: topY + 6, width: vW - hintX - pad - 26 - 6, height: 16)
        hint.alignment = .left
        hint.font      = .systemFont(ofSize: 10.5)
        hint.textColor = .tertiaryLabelColor
        view.addSubview(hint)

        // Botão sair — canto superior direito
        let quitBtn = NSButton(frame: NSRect(x: vW - pad - 22, y: topY + 2, width: 22, height: 22))
        quitBtn.title             = ""
        quitBtn.image             = NSImage(systemSymbolName: "xmark.circle.fill",
                                            accessibilityDescription: "Sair do Stash")
        quitBtn.contentTintColor  = .tertiaryLabelColor
        quitBtn.bezelStyle        = .inline
        quitBtn.isBordered        = false
        quitBtn.target            = self
        quitBtn.action            = #selector(quitApp)
        view.addSubview(quitBtn)

        // Campo de texto — sem anel de foco colorido
        textField = NSTextField(frame: NSRect(x: pad, y: pad, width: vW - pad * 2, height: 40))
        textField.placeholderString = "O que você precisa fazer?"
        textField.font              = .systemFont(ofSize: 14)
        textField.bezelStyle        = .roundedBezel
        textField.focusRingType     = .none
        textField.delegate          = self
        view.addSubview(textField)
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
        textField?.placeholderString = kIcons[index].placeholder
    }

    @objc private func quitApp() {
        let alert = NSAlert()
        alert.messageText     = "Encerrar o Stash?"
        alert.informativeText = "O app será removido da barra de menu e o hotkey deixará de funcionar."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Encerrar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func saveTask() {
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { dismiss(); return }

        if selectedIcon == "🔔" {
            let parsed = ReminderAIParser.parse(text)
            let reminderTitle = parsed?.title ?? text
            writeTask("\(selectedIcon) \(reminderTitle)")
            createReminder(title: reminderTitle, dueDate: parsed?.dueDate)
        } else {
            writeTask("\(selectedIcon) \(text)")
        }
        dismiss()
    }

    private func createReminder(title: String, dueDate: Date?) {
        let store = EKEventStore()
        let sem = DispatchSemaphore(value: 0)
        var granted = false

        store.requestFullAccessToReminders { ok, _ in
            granted = ok
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 8)
        guard granted else { return }

        let calendar = reminderCalendar(in: store)
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: TimeZone.current, from: dueDate)
        }

        try? store.save(reminder, commit: true)
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

    private func writeTask(_ task: String) {
        let indented = "    \(task)"
        let url = URL(fileURLWithPath: taskFilePath)

        let fmt = DateFormatter()
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
