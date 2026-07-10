import SwiftUI

// MARK: - StepperBar

/// Three-step flow indicator: ① 选中文件 → ② 点击目标 → ③ 完成
/// State is derived purely from SelectionStore + AppModel; no new state machine.
struct StepperBar: View {
    @EnvironmentObject private var selectionStore: SelectionStore
    @EnvironmentObject private var appModel: AppModel

    private var step: Int {
        if appModel.completionMoveCount != nil { return 3 }
        if selectionStore.selection.isEmpty { return 1 }
        return 2
    }

    var body: some View {
        HStack(spacing: 0) {
            StepItem(
                number: 1,
                label: stepOneLabel,
                state: stepOneState,
                isFlashing: appModel.stepOneFlash
            )
            StepConnector(active: step >= 2)
            StepItem(
                number: 2,
                label: "点击目标",
                state: stepTwoState,
                isFlashing: false
            )
            StepConnector(active: step >= 3)
            StepItem(
                number: 3,
                label: stepThreeLabel,
                state: stepThreeState,
                isFlashing: false
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .animation(.easeInOut(duration: 0.25), value: step)
        .animation(.easeInOut(duration: 0.25), value: appModel.stepOneFlash)
    }

    // MARK: - Derived state

    private var stepOneLabel: String {
        if step == 1 { return "选中文件" }
        let n = selectionStore.selection.count
        return n > 0 ? "已选 \(n)" : "选中文件"
    }

    private var stepThreeLabel: String {
        if let n = appModel.completionMoveCount {
            return "已移入 \(n) 项"
        }
        return "完成"
    }

    private var stepOneState: StepState {
        switch step {
        case 1: return .active
        case 2, 3: return .done
        default: return .idle
        }
    }

    private var stepTwoState: StepState {
        switch step {
        case 1: return .idle
        case 2: return .active
        case 3: return .done
        default: return .idle
        }
    }

    private var stepThreeState: StepState {
        step == 3 ? .complete : .idle
    }
}

// MARK: - Step state

private enum StepState {
    case idle, active, done, complete
}

// MARK: - StepItem

private struct StepItem: View {
    let number: Int
    let label: String
    let state: StepState
    let isFlashing: Bool

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(circleFill.opacity(isFlashing ? 0.5 : 0), lineWidth: 5)
                            .scaleEffect(isFlashing ? 1.6 : 1.0)
                            .opacity(isFlashing ? 0 : 1)
                    )

                if state == .done || state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(numberForeground)
                }
            }

            Text(label)
                .font(.caption)
                .fontWeight(state == .active || state == .complete ? .semibold : .regular)
                .foregroundStyle(labelColor)
        }
    }

    private var circleFill: Color {
        switch state {
        case .idle: return Color.secondary.opacity(0.3)
        case .active: return Color.accentColor
        case .done: return Color.green
        case .complete: return Color.green
        }
    }

    private var numberForeground: Color {
        state == .active ? .white : .secondary
    }

    private var labelColor: Color {
        switch state {
        case .idle: return .secondary
        case .active: return .primary
        case .done: return .secondary
        case .complete: return .green
        }
    }
}

// MARK: - StepConnector

private struct StepConnector: View {
    let active: Bool

    var body: some View {
        Rectangle()
            .fill(active ? Color.green.opacity(0.5) : Color.secondary.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 2)
            .padding(.horizontal, 4)
    }
}
