import Foundation

/// iPhone 5s ~ 6s 세대 ISP / 렌즈 특성을 재현하기 위한 파라미터 묶음.
/// 값은 모두 "기준 해상도 3264px 폭"을 전제로 하며, 실제 적용 시 해상도 비율로 스케일된다.
struct LookParameters: Equatable {

    // MARK: 1. 낮은 다이나믹 레인지
    /// 들린 블랙 (0 = 순검정 유지)
    var blackLift: Double = 0.055
    /// 눌린 하이라이트 (1 = 순백 유지)
    var highlightRolloff: Double = 0.935
    /// 중간톤 대비
    var midContrast: Double = 1.05

    // MARK: 2. 차갑고 옅은 색감
    /// 목표 화이트포인트 (6500K 기준보다 낮으면 차가워짐)
    var targetTemperature: Double = 5850
    /// + 값이면 마젠타, - 값이면 그린
    var targetTint: Double = 6
    var saturation: Double = 0.88

    // MARK: 3. 소프트 디테일 + ISP 샤프닝 헤일로
    /// 광학 해상력 부족을 흉내내는 미세 블러 (px @3264)
    var softness: Double = 1.0
    /// 블러 후 다시 거는 언샤프 — 5s 특유의 "가장자리만 또렷한" 느낌
    var sharpenIntensity: Double = 0.5
    var sharpenRadius: Double = 2.4

    // MARK: 4. 거친 노이즈
    /// 0 = 없음, 1 = 매우 거침
    var grainAmount: Double = 0.55
    /// 노이즈 알갱이 크기 (px @3264)
    var grainSize: Double = 2.2
    /// 1에 가까울수록 그림자/중간톤에만 노이즈가 몰림
    var shadowGrainBias: Double = 0.8

    // MARK: 5. 렌즈 특성
    var vignetteIntensity: Double = 0.55
    var vignetteRadius: Double = 1.4
    /// 광원 주변 베일링 글레어 (플레어)
    var glareAmount: Double = 0.30
    var glareRadius: Double = 10

    // MARK: 프리셋
    static let standard = LookParameters()

    /// 더 강하게 — 실내 저조도 5s 느낌
    static var strong: LookParameters {
        var p = LookParameters()
        p.blackLift = 0.075
        p.highlightRolloff = 0.90
        p.saturation = 0.82
        p.targetTemperature = 5700
        p.grainAmount = 0.85
        p.grainSize = 2.8
        p.softness = 1.4
        p.vignetteIntensity = 0.75
        p.glareAmount = 0.45
        return p
    }

    /// 룩 비활성 (원본 그대로)
    static var off: LookParameters {
        var p = LookParameters()
        p.blackLift = 0
        p.highlightRolloff = 1
        p.midContrast = 1
        p.targetTemperature = 6500
        p.targetTint = 0
        p.saturation = 1
        p.softness = 0
        p.sharpenIntensity = 0
        p.grainAmount = 0
        p.vignetteIntensity = 0
        p.glareAmount = 0
        return p
    }
}

enum LookPreset: String, CaseIterable, Identifiable {
    case standard = "5s"
    case strong   = "5s+"
    case off      = "OFF"

    var id: String { rawValue }

    var parameters: LookParameters {
        switch self {
        case .standard: return .standard
        case .strong:   return .strong
        case .off:      return .off
        }
    }
}
