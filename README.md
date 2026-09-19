# SNP — Something New Pic

iPhone 기본 카메라의 조작 감각은 그대로, 결과물은 iPhone 5s~6s 세대에 맞춘 카메라 앱.

## 열기

1. Finder 에서 `SNPCam.xcodeproj` 더블클릭
2. 좌측 상단 타깃 `SNPCam` → Signing & Capabilities 탭
3. **Team** 을 본인 Apple ID 로 선택 (무료 계정도 가능)
4. **Bundle Identifier** 를 고유한 값으로 변경 (예: `com.내이름.snpcam`)
5. 아이폰을 USB 로 연결 → 기기 선택 → ⌘R

> 카메라는 시뮬레이터에서 동작하지 않습니다. 반드시 실기기에서 실행하세요.
> 무료 개발자 계정은 앱이 7일마다 만료되며, 재설치하면 다시 사용할 수 있습니다.

- 최소 지원: **iOS 17**
- 방향: 세로 고정

## 프레임

| 모드 | 비율 | 저장 해상도 |
|---|---|---|
| 5:5 (기본) | 1:1 정사각 | 2448 × 2448 |
| 4:3 | 세로 3:4 | 2448 × 3264 |

두 비율 모두 4:3 센서에서 나오며, 5:5 는 가운데를 잘라 씁니다.
저장 해상도는 5s/6s 의 8MP 센서(3264×2448)에 맞춰 다운스케일합니다 —
룩 파라미터가 이 해상도 기준으로 튜닝돼 있어서, 해상도를 바꾸면 노이즈 결과 샤프닝 느낌이 달라집니다.

## 조작

| | |
|---|---|
| 화면 탭 | 그 지점에 초점 + 측광 |
| 길게 누르기 | 초점/노출 초기화 |
| 하단 슬라이더 | 노출 보정 (±EV) |
| 상단 좌측 | 플래시 (끔 / 자동 / 켬), 타이머 (끔 / 3초 / 10초) |
| 상단 우측 | 3분할 그리드, 수평계 |
| 하단 칩 | 비율 전환 (5:5 ↔ 4:3), 룩 전환 (5s / 5s+ / OFF) |
| 좌측 하단 썸네일 | 사진 앱 열기 |

타이머 카운트다운 중에 셔터를 다시 누르면 취소됩니다.

## 룩 — 5s~6s 재현

프리뷰와 저장본에 **완전히 같은 필터 체인**이 걸립니다. 보이는 그대로 찍힙니다.
`SNPCam/Look/LookParameters.swift` 의 숫자만 고치면 전체 톤이 바뀝니다.

| 단계 | 파라미터 | 재현하는 것 |
|---|---|---|
| 화이트밸런스 | `targetTemperature` 5850K, `targetTint` +6 | 차갑고 살짝 마젠타 기운 |
| 채도 | `saturation` 0.88 | 요즘 아이폰보다 옅은 색 |
| 톤 커브 | `blackLift` 0.055, `highlightRolloff` 0.935 | 낮은 다이나믹 레인지 — 들린 블랙, 쉽게 날아가는 하이라이트 |
| 글레어 | `glareAmount` 0.30 | 광원 주변 번짐 (플레어) |
| 소프트 디테일 | `softness` 1.0 → `sharpenIntensity` 0.5 | 광학 해상력 부족 + ISP 샤프닝 헤일로 |
| 그레인 | `grainAmount` 0.55, `grainSize` 2.2, `shadowGrainBias` 0.8 | 8MP 센서 노이즈 (그림자·중간톤에 집중) |
| 비네팅 | `vignetteIntensity` 0.55 | 렌즈 주변부 광량 저하 |

프리셋 세 개: `standard`(5s) / `strong`(5s+, 실내 저조도 느낌) / `off`(원본).

## 구조

```
SNPCam/
├─ App/        SNPCamApp.swift          앱 진입점
├─ Camera/     CameraManager.swift      세션·촬영·초점·노출
│              PreviewRenderer.swift    Metal 실시간 프리뷰 (필터 적용된 화면)
│              PhotoProcessor.swift     크롭 → 8MP 다운스케일 → 룩 → JPEG
│              PhotoCaptureDelegate.swift
│              FrameRatio.swift
├─ Look/       LookParameters.swift     ← 튜닝은 여기서
│              RetroLook.swift          Core Image 필터 체인
├─ UI/         CameraScreen.swift, Overlays.swift
└─ Support/    MotionManager.swift      수평계
```

기본 카메라처럼 `AVCaptureVideoPreviewLayer` 를 쓰지 않고, `AVCaptureVideoDataOutput` →
Core Image → `MTKView` 로 직접 그립니다. 그래야 프리뷰에도 룩이 걸립니다.

## 다음에 손볼 만한 것

- 배럴 디스토션 (5s 광각의 미세한 왜곡) — 현재는 비네팅만 적용
- 셔터 사운드 커스텀
- 룩 강도 슬라이더 (프리셋 대신 연속 조절)
- 촬영 직후 미리보기 화면
