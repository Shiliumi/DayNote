import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                if let active = store.activeTask {
                    Image(systemName: "timer")
                    Text("\(shortTitle(active.title)) \(ContentView.formatDuration(store.activeElapsed(at: context.date)))")
                        .monospacedDigit()
                } else {
                    Image(systemName: "note.text")
                    let total = store.totalElapsed(on: context.date, at: context.date)
                    if total > 0 {
                        Text(compactTotal(total))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func shortTitle(_ title: String) -> String {
        if title.count <= 8 { return title }
        return String(title.prefix(7)) + "…"
    }

    private func compactTotal(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let h = mins / 60
        let m = mins % 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

struct MenuBarContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: AppController

    private let accent = Color(red: 0.96, green: 0.43, blue: 0.27)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let tasks = store.tasks(on: now)
            let elapsed = store.totalElapsed(on: now, at: now)
            let goalMin = store.goalMinutes(on: now)
            let percent = StudyGoal.percent(elapsedSeconds: elapsed, goalMinutes: goalMin)
            let progress = StudyGoal.rate(elapsedSeconds: elapsed, goalMinutes: goalMin)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日便笺")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("达成 \(percent)% · \(ContentView.formatDuration(elapsed)) / \(StudyGoal.compactDurationLabel(minutes: goalMin))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if store.isTimerRunning {
                        Button {
                            store.pauseActiveTimer(at: now)
                        } label: {
                            Label("暂停", systemImage: "pause.fill")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.small)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule().fill(accent).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 5)

                Divider()

                if tasks.isEmpty {
                    Text("今天还没有任务，打开便笺添加吧")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(tasks) { task in
                                let running = store.activeDayKey == TaskStore.dayKey(for: now) && store.activeTaskID == task.id
                                HStack(spacing: 8) {
                                    Button {
                                        store.toggleCompletion(for: task.id, on: now, at: now)
                                    } label: {
                                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(task.isCompleted ? accent : .secondary)
                                    }
                                    .buttonStyle(.plain)

                                    Text(task.title)
                                        .font(.system(size: 12, weight: running ? .semibold : .regular, design: .rounded))
                                        .strikethrough(task.isCompleted)
                                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    Text(ContentView.formatDuration(store.elapsed(for: task, on: now, at: now)))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(running ? accent : .secondary)

                                    Button {
                                        store.toggleTimer(for: task.id, on: now, at: now)
                                    } label: {
                                        Image(systemName: running ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(task.isCompleted ? Color.secondary.opacity(0.35) : accent)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(task.isCompleted)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(running ? accent.opacity(0.10) : Color.clear)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }

                Divider()

                VStack(spacing: 4) {
                    menuRow("显示 / 隐藏便笺窗口", shortcut: "⌥Space", icon: "macwindow") {
                        controller.toggleMainWindow()
                    }
                    menuRow(controller.isMiniMode ? "展开完整便笺" : "切换迷你悬浮条", shortcut: nil, icon: controller.isMiniMode ? "arrow.up.left.and.arrow.down.right" : "rectangle.compress.vertical") {
                        controller.isMiniMode.toggle()
                        controller.showMainWindow()
                    }
                    menuRow("退出今日便笺", shortcut: "⌘Q", icon: "power") {
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    private func menuRow(_ title: String, shortcut: String?, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
