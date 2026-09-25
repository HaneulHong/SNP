import AVFoundation
import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var motion = MotionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.cameraDenied {
                PermissionView()
            } else {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 8)
                    previewFrame
                    exposureRow
                    Spacer(minLength: 8)
                    bottomBar
                }
            }

            if camera.shutterFlash {
                Color.black.ignoresSafeArea().transition(.opacity)
            }
        }
        .onAppear {
            camera.onAppear()
            motion.start()
        }
        .onDisappear {
            camera.onDisappear()
            motion.stop()
        }
        .onChange(of: camera.ratio) { _, _ in camera.syncLook() }
        .onChange(of: camera.lookPreset) { _, _ in camera.syncLook() }
        .onChange(of: scenePhase) { _, phase in
            // 기본 카메라처럼 앱을 벗어나면 녹화를 끝내고 저장한다
            if phase == .background { camera.stopRecording() }
        }
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack(spacing: 4) {
            TopToggle(systemName: flashIcon,
                      title: nil,
                      isActive: camera.flashMode != .off) { camera.cycleFlash() }

            TopToggle(systemName: "timer",
                      title: camera.timerSeconds > 0 ? "\(camera.timerSeconds)" : nil,
                      isActive: camera.timerSeconds > 0) { camera.cycleTimer() }

            Spacer()

            if let startedAt = camera.recordingStartedAt {
                RecordingClock(startedAt: startedAt)
                Spacer()
            }

            TopToggle(systemName: "grid",
                      title: nil,
                      isActive: camera.showsGrid) { camera.showsGrid.toggle() }

            TopToggle(systemName: "level",
                      title: nil,
                      isActive: camera.showsLevel) { camera.showsLevel.toggle() }
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }

    private var flashIcon: String {
        switch camera.flashMode {
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        default:    return "bolt.slash.fill"
        }
    }

    // MARK: - 프리뷰

    private var previewFrame: some View {
        GeometryReader { geo in
            ZStack {
                MetalPreviewView(renderer: camera.renderer)

                if camera.showsGrid { GridOverlay() }

                if camera.showsLevel {
                    LevelOverlay(rollDegrees: motion.rollDegrees)
                }

                if let indicator = camera.focusIndicator {
                    FocusReticle()
                        .position(indicator.point)
                        .id(indicator.id)
                }

                if camera.countdown > 0 {
                    Text("\(camera.countdown)")
                        .font(.system(size: 88, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let normalized = CGPoint(
                            x: min(max(value.location.x / geo.size.width, 0), 1),
                            y: min(max(value.location.y / geo.size.height, 0), 1)
                        )
                        camera.focus(atViewPoint: normalized, viewPoint: value.location)
                    }
            )
            .onLongPressGesture(minimumDuration: 0.6) {
                camera.resetFocus()
            }
        }
        .aspectRatio(camera.ratio.aspect, contentMode: .fit)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: camera.ratio)
    }

    // MARK: - 노출 슬라이더

    private var exposureRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            Slider(value: $camera.exposureBias,
                   in: camera.exposureRange,
                   step: 0.1)
            .tint(.yellow)

            Text(String(format: "%+.1f", camera.exposureBias))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(camera.exposureBias == 0 ? .white.opacity(0.6) : .yellow)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
    }

    // MARK: - 하단

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                // 녹화 중에는 파일 크기가 정해져 있어서 비율을 바꿀 수 없다
                chip(camera.ratio.label, active: camera.ratio == .fourThree) {
                    camera.toggleRatio()
                }
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.35 : 1)

                chip(camera.lookPreset.rawValue, active: camera.lookPreset != .off) {
                    camera.cycleLook()
                }
            }

            modePicker

            HStack {
                thumbnailButton
                Spacer()
                if camera.captureMode == .video {
                    RecordButton(isRecording: camera.isRecording) { shutterAction() }
                } else {
                    ShutterButton(isBusy: camera.isCapturing) { shutterAction() }
                }
                Spacer()
                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.35 : 1)
            }
            .padding(.horizontal, 34)
        }
        .padding(.bottom, 22)
    }

    private func shutterAction() {
        if camera.countdown > 0 {
            camera.cancelTimer()
        } else {
            camera.shutterTapped()
        }
    }

    /// 기본 카메라처럼 셔터 위의 "비디오 / 사진" 글자로 모드를 바꾼다
    private var modePicker: some View {
        HStack(spacing: 24) {
            modeButton("비디오", mode: .video)
            modeButton("사진", mode: .photo)
        }
        .opacity(camera.isRecording ? 0 : 1)
        .disabled(camera.isRecording)
    }

    private func modeButton(_ title: String, mode: CaptureMode) -> some View {
        Button {
            camera.setCaptureMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(camera.captureMode == mode ? Color.yellow : Color.white)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thumbnailButton: some View {
        Button {
            if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Group {
                if let image = camera.lastThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.10)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Color.yellow : Color.white.opacity(0.14),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44, weight: .thin))
            Text("카메라 접근 권한이 필요합니다")
                .font(.headline)
            Text("설정 › SNP 에서 카메라를 허용해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(40)
        .multilineTextAlignment(.center)
    }
}
