import Foundation

/// 옛날 캠코더(SD 480줄) 영상 특성을 재현하기 위한 파라미터 묶음.
/// 픽셀 단위 값은 모두 "기준 해상도 640px 긴 변"을 전제로 하며, 실제 프레임 크기에 맞춰 스케일된다.
struct CamcorderParameters: Equatable {

    // MARK: 1. CCD 색감
    /// 목표 화이트포인트 (6500K 보다 높으면 따뜻해짐)
    var targetTemperature: Double = 6800
    /// + 값이면 마젠타, - 값이면 그린
    var targetTint: Double = -2
    var saturation: Double = 1.10

    // MARK: 2. 좁은 비디오 레인지
    /// 들린 블랙
    var blackLift: Double = 0.035
    /// 화이트 상한 (1 = 순백)
    var whiteLevel: Double = 1.0
    /// 1 보다 크면 하이라이트가 빨리 하얗게 날아간다 — 캠코더 CCD 의 클리핑
    var contrast: Double = 1.12

    // MARK: 3. 렌즈
    /// 광학 해상력 부족 (px @640)
    var softness: Double = 0.5
    var vignetteIntensity: Double = 0.30
    var vignetteRadius: Double = 1.6

    // MARK: 4. 센서 노이즈 — 매 프레임 새로 뿌려져서 지글거린다
    /// 휘도 노이즈. SD 영상은 폰 화면에서 2~3배 확대돼 보이므로 사진 그레인보다 훨씬 약하게.
    var noiseAmount: Double = 0.07
    /// 색 노이즈 (그림자에 보이는 붉고 푸른 점)
    var chromaNoise: Double = 0.04
    /// 알갱이 크기 (px @640)
    var noiseSize: Double = 1.4
    /// 가로로 늘어나는 정도 (1 = 둥근 알갱이, 3 이상이면 테이프 특유의 가로 줄무늬 노이즈)
    var noiseStretch: Double = 1

    // MARK: 5. 에지 강조 — 캠코더 DSP 의 윤곽 보정, 경계에 하얀 테두리가 생긴다
    var edgeEnhance: Double = 0.8
    var edgeRadius: Double = 1.5

    // MARK: 6. 테이프 기록
    /// 색 번짐 — 색 해상도가 밝기보다 훨씬 낮아서 색이 가로로 흘러내린다 (px @640)
    var chromaBleed: Double = 3.0
    /// 색이 밝기보다 오른쪽으로 밀리는 정도 (px @640)
    var chromaShift: Double = 1.0
    /// 인터레이스 가로줄 (0 = 없음)
    var scanlines: Double = 0.04
    /// 프레임마다 가로로 흔들리는 폭 (px @640) — VHS 의 트래킹 불안정
    var jitter: Double = 0

    // MARK: 프리셋

    /// 2000년대 초 MiniDV 핸디캠 — 선명하고 쨍한 색, 하얀 윤곽선
    static let dv = CamcorderParameters()

    /// 90년대 VHS-C / 8mm — 뭉개지고 번지고 흔들리는 색
    static var vhs: CamcorderParameters {
        var p = CamcorderParameters()
        p.targetTemperature = 6300
        p.targetTint = 6
        p.saturation = 0.82
        p.blackLift = 0.07
        p.whiteLevel = 0.95
        p.contrast = 1.02
        p.softness = 1.4
        p.vignetteIntensity = 0.45
        p.noiseAmount = 0.11
        p.chromaNoise = 0.08
        p.noiseSize = 1.4
        p.noiseStretch = 4
        p.edgeEnhance = 0.9
        p.edgeRadius = 2.6
        p.chromaBleed = 7
        p.chromaShift = 2.5
        p.scanlines = 0.08
        p.jitter = 0.8
        return p
    }

    /// 룩 비활성 (원본 그대로 — 날짜 스탬프는 따로 켜고 끈다)
    static var off: CamcorderParameters {
        var p = CamcorderParameters()
        p.targetTemperature = 6500
        p.targetTint = 0
        p.saturation = 1
        p.blackLift = 0
        p.whiteLevel = 1
        p.contrast = 1
        p.softness = 0
        p.vignetteIntensity = 0
        p.noiseAmount = 0
        p.chromaNoise = 0
        p.edgeEnhance = 0
        p.chromaBleed = 0
        p.chromaShift = 0
        p.scanlines = 0
        p.jitter = 0
        return p
    }
}

enum CamcorderPreset: String, CaseIterable, Identifiable {
    case dv  = "DV"
    case vhs = "VHS"
    case off = "OFF"

    var id: String { rawValue }

    var parameters: CamcorderParameters {
        switch self {
        case .dv:  return .dv
        case .vhs: return .vhs
        case .off: return .off
        }
    }
}
