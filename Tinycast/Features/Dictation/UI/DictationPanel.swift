import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
    var startedAt = Date()
    @ObservationIgnored var onCancel: (() -> Void)?
}

private struct DictationWaveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.dictationWaveGap) {
            ForEach(levels.indices, id: \.self) { index in
                let emphasis = min(1, Double(min(index, levels.count - 1 - index)) / 3)
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.4 + 0.6 * emphasis))
                    .frame(
                        width: Theme.Size.dictationWaveBar,
                        height: 3 + 25 * CGFloat(levels[index]))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
    }
}

private struct DictationCancelButton: View {
    let state: DictationDisplayState
    @State private var hovered = false

    var body: some View {
        Button {
            state.onCancel?()
        } label: {
            Image(systemName: "xmark")
                .font(Theme.Typography.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: Theme.Size.dictationPanelCancel,
                    height: Theme.Size.dictationPanelCancel)
                .background(hovered ? Theme.Colors.controlHover : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeOut(duration: Theme.Duration.hover)) { self.hovered = hovered }
        }
        .accessibilityLabel("Cancel dictation")
    }
}

private struct DictationListeningRow: View {
    let state: DictationDisplayState

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            DictationWaveform(
                levels: state.levels.enumerated().map { index, level in
                    let edge = min(1, Float(min(index, state.levels.count - 1 - index)) / 4)
                    let taper = edge * edge * (3 - 2 * edge)
                    return level * (0.2 + 0.8 * taper)
                })
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.elapsed(from: state.startedAt, to: context.date))
                    .font(Theme.Typography.dictationTimer)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(minWidth: 36, alignment: .trailing)
                    .fixedSize()
            }
            DictationCancelButton(state: state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictation listening")
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct DictationTranscribingRow: View {
    let state: DictationDisplayState

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "progress.indicator")
                .foregroundStyle(Theme.Colors.progress)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            Text("Transcribing…")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textPrimary)
            DictationCancelButton(state: state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcribing dictation")
    }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState

    var body: some View {
        Group {
            if state.phase == .listening {
                DictationListeningRow(state: state)
            } else {
                DictationTranscribingRow(state: state)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(width: Theme.Size.dictationPanel.width, height: Theme.Size.dictationPanel.height)
        .glassEffect(.regular, in: .capsule)
    }
}

private final class DictationPanel: NSPanel {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.Size.dictationPanel),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onAccept?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class DictationPanelController {
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let panel =
            panel ?? DictationPanel(content: NSHostingView(rootView: DictationPanelView(state: state)))
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        state.onCancel = onCancel
        let size = Theme.Size.dictationPanel
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.1 - size.height / 2))
        state.phase = .listening
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        state.startedAt = Date()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
