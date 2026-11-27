import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: AppController
    @ObservedObject var clock: LiveClock

    var body: some View {
        let palette = controller.palette
        let now = clock.now
        let tasks = store.tasks(on: now)
        let elapsed = store.totalElapsed(on: now, at: now)
        let goalMin = store.goalMinutes(on: now)
        let percent = StudyGoal.percent(elapsedSeconds: elapsed, goalMinutes: goalMin)
        let progress = StudyGoal.rate(elapsedSeconds: elapsed, goalMinutes: goalMin)

        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(palette.accent.opacity(0.18), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percent)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("今日便笺")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if let remaining = controller.pomodoroRemainingSeconds(at: now) {
                        Text("🍅 番茄剩余 \(ContentView.formatDuration(remaining)) · 总计 \(ContentView.formatDuration(elapsed))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.accent)
                            .monospacedDigit()
                    } else {
                        Text("\(ContentView.formatDuration(elapsed)) / 目标 \(StudyGoal.compactDurationLabel(minutes: goalMin))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                if store.isTimerRunning {
                    Button {
                        store.pauseActiveTimer(at: now)
                        controller.updateStatusBarTitle()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(palette.accent))
                    }
                    .buttonStyle(.plain)
                    .help("暂停计时")
                }
            }

            Divider()

            if tasks.isEmpty {
                Text("今天还没有任务，打开便笺添加吧")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
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
                                        .foregroundStyle(task.isCompleted ? palette.accent : .secondary)
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
                                    .foregroundStyle(running ? palette.accent : .secondary)

                                Button {
                                    store.toggleTimer(for: task.id, on: now, at: now)
                                    controller.updateStatusBarTitle()
                                } label: {
                                    Image(systemName: running ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(task.isCompleted ? Color.secondary.opacity(0.35) : palette.accent)
                                }
                                .buttonStyle(.plain)
                                .disabled(task.isCompleted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(running ? palette.accent.opacity(0.11) : Color.clear)
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            VStack(spacing: 3) {
                menuRow("显示 / 隐藏便笺窗口", shortcut: "⌥Space", icon: "macwindow") {
                    controller.toggleMainWindow()
                }
                menuRow(controller.isMiniMode ? "展开完整便笺" : "切换迷你悬浮条", shortcut: nil, icon: controller.isMiniMode ? "arrow.up.left.and.arrow.down.right" : "rectangle.compress.vertical") {
                    controller.isMiniMode.toggle()
                    controller.showMainWindow()
                }
                menuRow(controller.pomodoroEnabled ? "关闭番茄倒计时（\(controller.pomodoroMinutes)分）" : "开启番茄倒计时（\(controller.pomodoroMinutes)分）", shortcut: nil, icon: "flame") {
                    controller.pomodoroEnabled.toggle()
                }
                menuRow("退出今日便笺", shortcut: "⌘Q", icon: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 312)
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
