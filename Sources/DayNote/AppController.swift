import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class AppController: ObservableObject {
    static weak var shared: AppController?

    @Published var isMiniMode: Bool {
        didSet { UserDefaults.standard.set(isMiniMode, forKey: Keys.miniMode) }
    }
    @Published var globalHotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotkeysEnabled, forKey: Keys.globalHotkeys)
            updateHotkeys()
        }
    }
    @Published var sleepProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(sleepProtectionEnabled, forKey: Keys.sleepProtection) }
    }
    @Published var sleepThresholdMinutes: Int {
        didSet { UserDefaults.standard.set(sleepThresholdMinutes, forKey: Keys.sleepThreshold) }
    }
    @Published var focusReminderMinutes: Int {
        didSet {
            UserDefaults.standard.set(focusReminderMinutes, forKey: Keys.focusReminderMinutes)
            resetFocusReminderTracking()
        }
    }
    @Published var sleepPrompt: SleepRecoveryPrompt?
    @Published var focusReminderMessage: String?
    @Published var launchAtLoginError: String?

    weak var mainWindow: NSWindow?
    private weak var store: TaskStore?

    private var awayStartedAt: Date?
    private var awayTaskID: UUID?
    private var awayDayKey: String?
    private var awayTaskTitle: String?

    private var trackedTimerStart: Date?
    private var lastNotifiedMilestone: Int = 0

    private var hotKeyEventHandler: EventHandlerRef?
    private var toggleWindowHotKeyRef: EventHotKeyRef?
    private var toggleTimerHotKeyRef: EventHotKeyRef?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private enum Keys {
        static let miniMode = "daynote.mini-mode"
        static let globalHotkeys = "daynote.global-hotkeys"
        static let sleepProtection = "daynote.sleep-protection"
        static let sleepThreshold = "daynote.sleep-threshold-minutes"
        static let focusReminderMinutes = "daynote.focus-reminder-minutes"
    }

    init() {
        let defaults = UserDefaults.standard
        self.isMiniMode = defaults.bool(forKey: Keys.miniMode)
        self.globalHotkeysEnabled = defaults.object(forKey: Keys.globalHotkeys) as? Bool ?? true
        self.sleepProtectionEnabled = defaults.object(forKey: Keys.sleepProtection) as? Bool ?? true
        let savedThreshold = defaults.integer(forKey: Keys.sleepThreshold)
        self.sleepThresholdMinutes = savedThreshold > 0 ? savedThreshold : 3
        self.focusReminderMinutes = defaults.integer(forKey: Keys.focusReminderMinutes)

        Self.shared = self
        installSleepObservers()
        updateHotkeys()
    }

    func attach(store: TaskStore) {
        self.store = store
    }

    // MARK: - Window Management

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func toggleMainWindow() {
        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if window.isVisible && NSApp.isActive && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    // MARK: - Login Item

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
        } catch {
            launchAtLoginError = "设置开机自启失败（建议将 DayNote.app 拖入“应用程序”文件夹后重试）：\(error.localizedDescription)"
        }
    }

    // MARK: - Focus Reminder (Pomodoro)

    func evaluateFocusReminder(at now: Date) {
        guard focusReminderMinutes > 0, let store, store.isTimerRunning, let started = store.timerStartedAt else {
            resetFocusReminderTracking()
            return
        }
        if trackedTimerStart != started {
            trackedTimerStart = started
            lastNotifiedMilestone = 0
        }
        let elapsedMinutes = Int(max(0, now.timeIntervalSince(started)) / 60)
        let milestone = elapsedMinutes / focusReminderMinutes
        if milestone > lastNotifiedMilestone && milestone > 0 {
            lastNotifiedMilestone = milestone
            let totalMins = milestone * focusReminderMinutes
            let taskName = store.activeTask?.title ?? "当前任务"
            triggerFocusReminder(taskName: taskName, minutes: totalMins)
        }
    }

    func dismissFocusReminder() {
        focusReminderMessage = nil
    }

    func pauseForBreak() {
        store?.pauseActiveTimer()
        focusReminderMessage = nil
    }

    private func resetFocusReminderTracking() {
        trackedTimerStart = nil
        lastNotifiedMilestone = 0
    }

    private func triggerFocusReminder(taskName: String, minutes: Int) {
        let message = "已专注「\(taskName)」\(minutes) 分钟，起来活动一下吧"
        focusReminderMessage = message
        NSSound(named: NSSound.Name("Glass"))?.play()
        postLocalNotification(title: "今日便笺 · 专注提醒", body: message)
    }

    private func postLocalNotification(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "daynote.focus.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    // MARK: - Sleep & Lock Protection

    private func installSleepObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let sleepNames: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification
        ]
        for name in sleepNames {
            let obs = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.recordAwayStart()
                }
            }
            workspaceObservers.append(obs)
        }

        let wakeNames: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]
        for name in wakeNames {
            let obs = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleReturnFromAway()
                }
            }
            workspaceObservers.append(obs)
        }

        let distCenter = DistributedNotificationCenter.default()
        let lockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordAwayStart()
            }
        }
        let unlockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleReturnFromAway()
            }
        }
        distributedObservers.append(contentsOf: [lockObs, unlockObs])
    }

    private func recordAwayStart() {
        guard sleepProtectionEnabled, awayStartedAt == nil, let store, store.isTimerRunning,
              let dayKey = store.activeDayKey, let taskID = store.activeTaskID, let task = store.activeTask else {
            return
        }
        awayStartedAt = Date()
        awayDayKey = dayKey
        awayTaskID = taskID
        awayTaskTitle = task.title
    }

    private func handleReturnFromAway() {
        defer {
            awayStartedAt = nil
            awayDayKey = nil
            awayTaskID = nil
            awayTaskTitle = nil
        }
        guard sleepProtectionEnabled,
              let started = awayStartedAt,
              let dayKey = awayDayKey,
              let taskID = awayTaskID,
              let title = awayTaskTitle else {
            return
        }
        let awaySeconds = Date().timeIntervalSince(started)
        guard awaySeconds >= TimeInterval(max(1, sleepThresholdMinutes) * 60) else { return }
        sleepPrompt = SleepRecoveryPrompt(
            dayKey: dayKey,
            taskID: taskID,
            taskTitle: title,
            awaySeconds: awaySeconds
        )
        showMainWindow()
    }

    func resolveSleepPrompt(deduct: Bool, pause: Bool) {
        guard let prompt = sleepPrompt else { return }
        if deduct {
            store?.deductAwayTime(
                taskID: prompt.taskID,
                dayKey: prompt.dayKey,
                seconds: prompt.awaySeconds,
                pauseTimer: pause
            )
        } else if pause {
            store?.pauseActiveTimer()
        }
        sleepPrompt = nil
    }

    // MARK: - Global Hotkeys (Carbon)

    private func updateHotkeys() {
        unregisterHotkeys()
        guard globalHotkeysEnabled else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            dayNoteHotKeyCallback,
            1,
            &eventSpec,
            nil,
            &hotKeyEventHandler
        )
        guard status == noErr else { return }

        let signature: OSType = 0x444E5445 // 'DNTE'
        // Option + Space -> Toggle main window
        let winHotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            winHotKeyID,
            GetApplicationEventTarget(),
            0,
            &toggleWindowHotKeyRef
        )
        // Option + Shift + Space -> Toggle timer
        let timerHotKeyID = EventHotKeyID(signature: signature, id: 2)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey | shiftKey),
            timerHotKeyID,
            GetApplicationEventTarget(),
            0,
            &toggleTimerHotKeyRef
        )
    }

    private func unregisterHotkeys() {
        if let ref = toggleWindowHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleWindowHotKeyRef = nil
        }
        if let ref = toggleTimerHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleTimerHotKeyRef = nil
        }
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
            hotKeyEventHandler = nil
        }
    }

    fileprivate func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            toggleMainWindow()
        case 2:
            store?.toggleQuickTimer()
        default:
            break
        }
    }
}

private func dayNoteHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        let id = hotKeyID.id
        Task { @MainActor in
            AppController.shared?.handleHotKey(id: id)
        }
    }
    return noErr
}
