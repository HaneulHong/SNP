# SNP — Something New Pic

iPhone 기본 카메라의 조작 감각은 그대로, 결과물은 iPhone 5s~6s 세대에 맞춘 카메라 앱.
사진은 5s 룩, 비디오는 옛날 캠코더 룩. 렌즈는 하나만 쓴다.

## 아이폰에서 실행하기

처음 한 번만:

1. **Xcode 에 Apple ID 로그인** — Xcode › Settings › Accounts › `+` › Apple ID (무료 계정 가능)
2. **아이폰 개발자 모드 켜기** — 아이폰 설정 › 개인정보 보호 및 보안 › 맨 아래 **개발자 모드** 켬 → 재시동 → 잠금 해제 후 "켜기"
   (메뉴가 안 보이면 아이폰을 USB 로 연결한 채 Xcode 를 한 번 열어두면 나타난다)
3. Finder 에서 `SNPCam.xcodeproj` 더블클릭 → 좌측 `SNPCam` 타깃 › Signing & Capabilities › **Team** 을 본인 이름(Personal Team)으로
4. 상단 기기 목록에서 연결된 아이폰 선택 → ⌘R
5. 처음 실행 때 "신뢰할 수 없는 개발자" 가 뜨면 아이폰 설정 › 일반 › VPN 및 기기 관리 › 본인 Apple ID › **신뢰**

> 카메라는 시뮬레이터에서 동작하지 않습니다 (화면 배치만 확인 가능). 반드시 실기기에서 실행하세요.
> 무료 개발자 계정은 앱이 7일마다 만료되며, 다시 ⌘R 하면 된다.
> 번들 ID `com.haneulhong.snpcam` 이 이미 쓰인다는 오류가 나면 끝에 아무 글자나 붙여 바꾸면 된다.

- 최소 지원: **iOS 17**
- 방향: 세로 고정

## 렌즈 하나 — 옛날 아이폰처럼

요즘 아이폰은 후면 카메라가 2~3개고, 줌·접사 때 렌즈를 알아서 바꾼다.
이 앱은 **메인 광각 물리 렌즈 하나만** 쓰고 (`LegacyLens.swift`), 렌즈를 바꾸는 가상 멀티카메라는 절대 쓰지 않는다.

- **화각 고정** — 6/6s 후면은 35mm 환산 29mm, 요즘 메인은 24~26mm 로 더 넓다.
  가운데를 디지털로 잘라 29mm 화각에 맞춘다 (14 Pro 기준 ×1.21). 전면은 FaceTime HD 31mm 에 맞춘다.
  잘라도 저장 해상도(8MP)보다 센서 픽셀이 많아서 화질 손해는 없다.
- **줌 없음** — 핀치 줌, 0.5×/3× 버튼 없음. 발로 움직인다.
- 전면 센터 스테이지(자동 프레이밍), 비디오 HDR 끔.

## 비디오 — 캠코더 룩

셔터 위 **비디오 / 사진** 을 눌러 전환. 비디오는 SD 4:3 (640×480) 30fps 로 기록되고 사진 보관함에 저장된다.
**폰을 가로로 들고 녹화 버튼을 누르면 가로 영상**(640×480), 세로면 세로 영상(480×640). 녹화 도중엔 방향이 고정된다.

| | |
|---|---|
| 하단 칩 `DV` / `VHS` / `OFF` | 룩 전환 |
| 하단 칩 `DATE` | 오른쪽 아래 날짜 스탬프 (`10:16:32 PM` / `SEP. 25 2026`) |
| 상단 좌측 | 손전등 (후면만) |

프리뷰와 파일에 **같은 프레임**을 쓴다 — 보이는 그대로 기록된다. `SNPCam/Look/CamcorderParameters.swift` 에서 튜닝.

| 단계 | 파라미터 | 재현하는 것 |
|---|---|---|
| CCD 색 | `targetTemperature`, `targetTint`, `saturation` | DV: 따뜻하고 쨍함 / VHS: 물 빠지고 마젠타 |
| 비디오 레인지 | `blackLift`, `whiteLevel`, `contrast` | 뜬 블랙, 쉽게 하얗게 날아가는 하이라이트 |
| 렌즈 | `softness`, `vignetteIntensity` | 해상력 부족, 주변부 어두움 |
| 센서 노이즈 | `noiseAmount`, `chromaNoise`, `noiseStretch` | 매 프레임 지글거리는 노이즈 (VHS 는 가로로 늘어진 테이프 노이즈) |
| 에지 강조 | `edgeEnhance`, `edgeRadius` | 경계의 하얀 테두리 — 캠코더 DSP 특유 |
| 날짜 스탬프 | — | 도트 폰트. 테이프에 같이 기록된 것처럼 아래 번짐을 같이 먹는다 |
| 테이프 | `chromaBleed`, `chromaShift` | 색이 가로로 흘러내리고 오른쪽으로 밀림 |
| 인터레이스 | `scanlines` | 가는 가로줄 |
| 트래킹 | `jitter` | VHS 의 가로 흔들림 |

소리는 마이크로 함께 녹음한다 (권한 거부 시 무음으로 기록). 사진 모드에선 마이크를 놓는다.

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
├─ Camera/     CameraManager.swift      세션·모드 전환·촬영·녹화·초점·노출
│              LegacyLens.swift         렌즈 하나 고정 + 5s~6s 화각
│              PreviewRenderer.swift    Metal 실시간 프리뷰 (필터 적용된 화면)
│              PhotoProcessor.swift     크롭 → 8MP 다운스케일 → 룩 → JPEG
│              PhotoCaptureDelegate.swift  (+ 보관함 저장)
│              VideoRecorder.swift      룩 입힌 프레임 + 소리 → .mov
│              CaptureMode.swift        사진/비디오, 기록 방향
│              FrameRatio.swift
├─ Look/       LookParameters.swift     ← 사진 튜닝은 여기서
│              RetroLook.swift          사진 필터 체인
│              CamcorderParameters.swift ← 비디오 튜닝은 여기서
│              CamcorderLook.swift      비디오 필터 체인 + 날짜 스탬프
├─ UI/         CameraScreen.swift, Overlays.swift
└─ Support/    MotionManager.swift      수평계 + 기기 방향
```

기본 카메라처럼 `AVCaptureVideoPreviewLayer` 를 쓰지 않고, `AVCaptureVideoDataOutput` →
Core Image → `MTKView` 로 직접 그립니다. 그래야 프리뷰에도 룩이 걸립니다.
비디오도 같은 이유로 `AVCaptureMovieFileOutput` 대신 `AVAssetWriter` 로 프레임을 직접 인코딩합니다.

## 다음에 손볼 만한 것

- 사진도 가로로 들면 가로로 저장 (지금은 비디오만 방향을 따른다)
- 배럴 디스토션 (5s 광각의 미세한 왜곡) — 현재는 비네팅만 적용
- 셔터 사운드 커스텀
- 룩 강도 슬라이더 (프리셋 대신 연속 조절)
- 촬영 직후 미리보기 화면
- 캠코더 소리 (좁은 대역 · 테이프 히스)
