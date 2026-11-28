import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class LiveClock: ObservableObject {
    @Published var now: Date = Date()
}

@MainActor
final class AppController: NSObject, ObservableObject, NSPopoverDelegate {
    static weak var shared: AppController?

    let clock = LiveClock()

    @Published var themeID: DayNoteThemeID {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: Keys.themeID) }
    }
    @Published var windowOpacity: Double {
        didSet { UserDefaults.standard.set(windowOpacity, forKey: Keys.windowOpacity) }
    }
    @Published var isMiniMode: Bool {
        didSet { UserDefaults.standard.set(isMiniMode, forKey: Keys.miniMode) }
    }
    @Published var globalHotkeysEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotkeysEnabled, forKey: Keys.globalHotkeys)
            if hasStarted { updateHotkeys() }
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
    @Published var pomodoroEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pomodoroEnabled, forKey: Keys.pomodoroEnabled)
            resetPomodoroTracking()
            updateStatusBarTitle()
        }
    }
    @Published var pomodoroMinutes: Int {
        didSet {
            UserDefaults.standard.set(pomodoroMinutes, forKey: Keys.pomodoroMinutes)
            resetPomodoroTracking()
            updateStatusBarTitle()
        }
    }
    @Published var sleepPrompt: SleepRecoveryPrompt?
    @Published var focusReminderMessage: String?
    @Published var launchAtLoginError: String?

    var palette: DayNotePalette { themeID.palette }

    weak var mainWindow: NSWindow?
    private weak var store: TaskStore?
    private var hasStarted = false

    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var activeTickTimer: Timer?
    private var dayRolloverTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private lazy var timerSymbolImage: NSImage? = {
        let img = NSImage(systemSymbolName: "timer", accessibilityDescription: "计时中")
        img?.isTemplate = true
        return img
    }()

    private lazy var noteSymbolImage: NSImage? = {
        let img = NSImage(systemSymbolName: "note.text", accessibilityDescription: "今日便笺")
        img?.isTemplate = true
        return img
    }()

    private lazy var pomodoroSymbolImage: NSImage? = {
        let img = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "番茄专注中")
        img?.isTemplate = true
        return img
    }()

    private var awayStartedAt: Date?
    private var awayTaskID: UUID?
    private var awayDayKey: String?
    private var awayTaskTitle: String?
    private var isScreenLocked = false

    private var trackedTimerStart: Date?
    private var lastNotifiedMilestone: Int = 0
    private var completedPomodoroForStart: Date?
    private var lastObservedDayKey: String = TaskStore.dayKey(for: Date())

    private var hotKeyEventHandler: EventHandlerRef?
    private var toggleWindowHotKeyRef: EventHotKeyRef?
    private var toggleTimerHotKeyRef: EventHotKeyRef?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private enum Keys {
        static let themeID = "daynote.theme-id"
        static let windowOpacity = "daynote.window-opacity"
        static let miniMode = "daynote.mini-mode"
        static let globalHotkeys = "daynote.global-hotkeys"
        static let sleepProtection = "daynote.sleep-protection"
        static let sleepThreshold = "daynote.sleep-threshold-minutes"
        static let focusReminderMinutes = "daynote.focus-reminder-minutes"
        static let pomodoroEnabled = "daynote.pomodoro-enabled"
        static let pomodoroMinutes = "daynote.pomodoro-minutes"
    }

    override init() {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.string(forKey: Keys.themeID).flatMap(DayNoteThemeID.init(rawValue:)) ?? .warmApricot
        self.themeID = savedTheme
        let savedOpacity = defaults.object(forKey: Keys.windowOpacity) as? Double ?? 1.0
        self.windowOpacity = min(1.0, max(0.75, savedOpacity))
        self.isMiniMode = defaults.bool(forKey: Keys.miniMode)
        self.globalHotkeysEnabled = defaults.object(forKey: Keys.globalHotkeys) as? Bool ?? true
        self.sleepProtectionEnabled = defaults.object(forKey: Keys.sleepProtection) as? Bool ?? true
        let savedThreshold = defaults.integer(forKey: Keys.sleepThreshold)
        self.sleepThresholdMinutes = savedThreshold > 0 ? savedThreshold : 3
        self.focusReminderMinutes = defaults.integer(forKey: Keys.focusReminderMinutes)
        self.pomodoroEnabled = defaults.bool(forKey: Keys.pomodoroEnabled)
        let savedPomo = defaults.integer(forKey: Keys.pomodoroMinutes)
        self.pomodoroMinutes = savedPomo > 0 ? savedPomo : 25

        super.init()
        Self.shared = self
    }

    func attach(store: TaskStore) {
        self.store = store
        cancellables.removeAll()

        store.$activeTaskID
            .combineLatest(store.$timerStartedAt)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncTimersWithRunningState()
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)

        store.$days
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
    }

    /// Called once NSApplication finishes launching so AppKit/Carbon/StatusBar are fully initialized.
    func startSystemIntegrations() {
        guard !hasStarted else { return }
        hasStarted = true
        setupStatusBarItem()
        installSleepObservers()
        installAppActiveObserver()
        updateHotkeys()
        syncTimersWithRunningState()
        startDayRolloverTimer()
    }

    private func installAppActiveObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshClockAndDayState()
            }
        }
        workspaceObservers.append(obs)
    }

    func refreshClockAndDayState() {
        let now = Date()
        clock.now = now
        let currentKey = TaskStore.dayKey(for: now)
        if currentKey != lastObservedDayKey {
            lastObservedDayKey = currentKey
            store?.prepareForCurrentDay(at: now)
        }
        updateStatusBarTitle(at: now)
    }

    // MARK: - Smart Low-Power Ticker (0 Hz when idle, 1 Hz only while timing)

    private func syncTimersWithRunningState() {
        let running = store?.isTimerRunning == true
        if running {
            guard activeTickTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.handleActiveTick()
                }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            activeTickTimer = timer
            handleActiveTick()
        } else {
            activeTickTimer?.invalidate()
            activeTickTimer = nil
            clock.now = Date()
            resetFocusReminderTracking()
            resetPomodoroTracking()
        }
    }

    private func startDayRolloverTimer() {
        dayRolloverTimer?.invalidate()
        let timer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkDayRollover()
            }
        }
        timer.tolerance = 15.0
        RunLoop.main.add(timer, forMode: .common)
        dayRolloverTimer = timer
    }

    private func checkDayRollover() {
        let now = Date()
        let currentKey = TaskStore.dayKey(for: now)
        if currentKey != lastObservedDayKey {
            lastObservedDayKey = currentKey
            store?.prepareForCurrentDay(at: now)
            clock.now = now
            updateStatusBarTitle()
        }
    }

    private func handleActiveTick() {
        let now = Date()
        clock.now = now
        let currentKey = TaskStore.dayKey(for: now)
        if currentKey != lastObservedDayKey {
            lastObservedDayKey = currentKey
            store?.prepareForCurrentDay(at: now)
        }
        evaluatePomodoro(at: now)
        evaluateFocusReminder(at: now)
        updateStatusBarTitle(at: now)
    }

    // MARK: - Pomodoro Countdown

    func pomodoroRemainingSeconds(at now: Date) -> TimeInterval? {
        guard pomodoroEnabled, let store, store.isTimerRunning, let started = store.timerStartedAt else {
            return nil
        }
        let target = TimeInterval(max(1, pomodoroMinutes) * 60)
        let elapsed = max(0, now.timeIntervalSince(started))
        return max(0, target - elapsed)
    }

    func pomodoroProgress(at now: Date) -> Double {
        guard pomodoroEnabled, let store, store.isTimerRunning, let started = store.timerStartedAt else {
            return 0
        }
        let target = TimeInterval(max(1, pomodoroMinutes) * 60)
        let elapsed = max(0, now.timeIntervalSince(started))
        return min(1, elapsed / target)
    }

    private func evaluatePomodoro(at now: Date) {
        guard awayStartedAt == nil, sleepPrompt == nil else { return }
        guard pomodoroEnabled, let store, store.isTimerRunning, let started = store.timerStartedAt else {
            resetPomodoroTracking()
            return
        }
        guard completedPomodoroForStart != started else { return }
        let target = TimeInterval(max(1, pomodoroMinutes) * 60)
        if now.timeIntervalSince(started) >= target {
            completedPomodoroForStart = started
            let taskName = store.activeTask?.title ?? "当前任务"
            store.incrementPomodoro(on: now)
            store.pauseActiveTimer(at: now)
            let count = store.pomodoroCount(on: now)
            let message = "完成第 \(count) 个番茄（\(pomodoroMinutes) 分钟 · \(taskName)），休息一下吧！"
            focusReminderMessage = message
            NSSound(named: NSSound.Name("Glass"))?.play()
            postLocalNotification(title: "🍅 番茄钟完成", body: message)
            showMainWindow()
        }
    }

    private func resetPomodoroTracking() {
        completedPomodoroForStart = nil
    }

    // MARK: - Native Menu Bar Status Item (NSStatusBar + Lazy NSPopover)

    private func setupStatusBarItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        statusPopover = popover

        updateStatusBarTitle()
    }

    func updateStatusBarTitle(at now: Date = Date()) {
        guard let button = statusItem?.button, let store else { return }
        if let active = store.activeTask {
            let title = shortTitle(active.title)
            if let remaining = pomodoroRemainingSeconds(at: now) {
                button.image = pomodoroSymbolImage
                button.title = " \(title) \(ContentView.formatDuration(remaining))"
            } else {
                button.image = timerSymbolImage
                button.title = " \(title) \(ContentView.formatDuration(store.activeElapsed(at: now)))"
            }
        } else {
            button.image = noteSymbolImage
            let total = store.totalElapsed(on: now, at: now)
            if total > 0 {
                let mins = Int(total) / 60
                let h = mins / 60
                let m = mins % 60
                button.title = h > 0 ? " \(h)h\(m)m" : " \(m)m"
            } else {
                button.title = ""
            }
        }
    }

    private func shortTitle(_ title: String) -> String {
        if title.count <= 8 { return title }
        return String(title.prefix(7)) + "…"
    }

    @objc private func toggleStatusPopover(_ sender: AnyObject?) {
        guard let popover = statusPopover, let button = statusItem?.button, let store else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshClockAndDayState()
            popover.contentViewController = NSHostingController(
                rootView: MenuBarContentView(store: store, controller: self, clock: clock)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            // Release view hierarchy while closed so idle memory & CPU stay near zero.
            self.statusPopover?.contentViewController = nil
        }
    }

    func closeStatusPopover() {
        statusPopover?.performClose(nil)
    }

    // MARK: - Window Management

    func showMainWindow() {
        closeStatusPopover()
        refreshClockAndDayState()
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func toggleMainWindow() {
        closeStatusPopover()
        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) else {
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

    // MARK: - Focus Reminder

    func evaluateFocusReminder(at now: Date) {
        guard awayStartedAt == nil, sleepPrompt == nil else { return }
        guard !pomodoroEnabled, focusReminderMinutes > 0, let store, store.isTimerRunning, let started = store.timerStartedAt else {
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
                    guard let self, !self.isScreenLocked else { return }
                    self.handleReturnFromAway()
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
                self?.isScreenLocked = true
                self?.recordAwayStart()
            }
        }
        let unlockObs = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isScreenLocked = false
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
        refreshClockAndDayState()
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
        let winHotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            winHotKeyID,
            GetApplicationEventTarget(),
            0,
            &toggleWindowHotKeyRef
        )
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
            updateStatusBarTitle()
        default:
            break
        }
    }
}

final class DayNoteAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppController.shared?.startSystemIntegrations()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            AppController.shared?.showMainWindow()
        }
        return true
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
