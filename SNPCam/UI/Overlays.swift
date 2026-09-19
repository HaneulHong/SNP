import SwiftUI

/// 3분할 그리드
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// 수평계 — 기울면 회전하는 선, 수평이면 노란색
struct LevelOverlay: View {
    let rollDegrees: Double
    var isLevel: Bool { abs(rollDegrees) < 1.0 }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 92, height: 1)

            Rectangle()
                .fill(isLevel ? Color.yellow : Color.white.opacity(0.9))
                .frame(width: 92, height: isLevel ? 2 : 1)
                .rotationEffect(.degrees(isLevel ? 0 : -rollDegrees))
                .animation(.linear(duration: 0.06), value: rollDegrees)
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .allowsHitTesting(false)
    }
}

/// 탭 포커스 사각형
struct FocusReticle: View {
    @State private var scale: CGFloat = 1.35
    @State private var opacity: Double = 0

    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) {
                    scale = 1.0
                    opacity = 1
                }
                withAnimation(.easeIn(duration: 0.4).delay(1.6)) {
                    opacity = 0.35
                }
            }
            .allowsHitTesting(false)
    }
}

/// 기본 카메라와 같은 이중 원 셔터
struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
                    .scaleEffect(pressed ? 0.86 : 1)
                    .opacity(isBusy ? 0.45 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.08)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = false } }
        )
    }
}

/// 상단 아이콘 토글
struct TopToggle: View {
    let systemName: String
    let title: String?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(isActive ? Color.yellow : Color.white)
            .frame(minWidth: 42, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
