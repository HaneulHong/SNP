import AVFoundation
import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var motion = MotionManager()
    /// 핀치를 시작할 때의 줌 — 핀치 배율을 여기에 곱한다
    @State private var pinchStartZoom: CGFloat?

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
        .onChange(of: motion.captureOrientation, initial: true) { _, orientation in
            camera.updateOrientation(orientation)
        }
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack(spacing: 4) {
            if camera.mode == .photo {
                TopToggle(systemName: flashIcon,
                          title: nil,
                          isActive: camera.flashMode != .off) { camera.cycleFlash() }

                TopToggle(systemName: "timer",
                          title: camera.timerSeconds > 0 ? "\(camera.timerSeconds)" : nil,
                          isActive: camera.timerSeconds > 0) { camera.cycleTimer() }
            } else {
                TopToggle(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                          title: nil,
                          isActive: camera.torchOn) { camera.toggleTorch() }
                    .opacity(camera.position == .back ? 1 : 0.3)
            }

            Spacer()

            TopToggle(systemName: "grid",
                      title: nil,
                      isActive: camera.showsGrid) { camera.showsGrid.toggle() }

            TopToggle(systemName: "level",
                      title: nil,
                      isActive: camera.showsLevel) { camera.showsLevel.toggle() }
        }
        .overlay {
            if camera.isRecording {
                RecordingTime(duration: camera.recordingDuration)
            }
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

                // 1× ⇄ 2× (minilux zoom 의 35 → 70mm), 핀치로 최대 4×
                ZoomBadge(zoom: camera.zoom) {
                    camera.setZoom(camera.zoom < 1.01 ? 2 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)

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
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStartZoom ?? camera.zoom
                        if pinchStartZoom == nil { pinchStartZoom = start }
                        camera.setZoom(start * value.magnification)
                    }
                    .onEnded { _ in pinchStartZoom = nil }
            )
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
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // 비율(3:2 / 5:5)·날짜는 사진·비디오 공통. 기본(3:2)이 아닐 때만 노랗게
                chip(camera.ratio.label, active: camera.ratio == .square) {
                    camera.toggleRatio()
                }
                if camera.mode == .photo {
                    chip(camera.lookPreset.rawValue, active: true) {
                        camera.cycleLook()
                    }
                } else {
                    chip(camera.camcorderPreset.rawValue, active: camera.camcorderPreset != .off) {
                        camera.cycleCamcorder()
                    }
                }
                // 사진은 필름 날짜('26 9 26), 비디오는 캠코더 날짜·시각
                chip("DATE", active: camera.showsDateStamp) {
                    camera.toggleDateStamp()
                }
            }
            .disabled(camera.isRecording)

            // 녹화 중엔 모드를 바꿀 수 없으니 숨긴다 (자리는 유지)
            ModePicker(selection: camera.mode) { camera.setMode($0) }
                .opacity(camera.isRecording ? 0 : 1)
                .disabled(camera.isRecording)

            HStack {
                thumbnailButton
                Spacer()
                if camera.mode == .photo {
                    ShutterButton(isBusy: camera.isCapturing) {
                        if camera.countdown > 0 {
                            camera.cancelTimer()
                        } else {
                            camera.shutterTapped()
                        }
                    }
                } else {
                    RecordButton(isRecording: camera.isRecording) {
                        camera.recordTapped()
                    }
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
                .opacity(camera.isRecording ? 0.3 : 1)
                .disabled(camera.isRecording)
            }
            .padding(.horizontal, 34)
        }
        .padding(.bottom, 16)
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
