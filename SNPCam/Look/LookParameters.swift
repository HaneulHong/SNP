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
    /// 1 보다 크면 중간톤이 가라앉는다 — 요즘 옛날 아이폰에서 찾는 "어두운" 느낌
    var midGamma: Double = 1.0

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

    /// 뿌연 헤이즈 — 흐린 사본을 밝은 쪽만 얹어 잡티를 묻고 피부를 뽀얗게 (0 = 없음)
    /// 요즘 옛날 아이폰을 찾는 가장 큰 이유: 보정 없이도 얼굴이 부드럽게 나온다
    var hazeAmount: Double = 0.25
    /// px @3264 — 잡티 크기 정도
    var hazeRadius: Double = 14

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

    // MARK: 6. 센서
    /// 저장 해상도의 긴 변 — 3264 = 8MP (5s), 4032 = 12MP (6s)
    var sensorLongSide: Double = 3264
    /// 셀카 저장 해상도의 긴 변 — 1280 = 1.2MP (5s 전면), 2576 = 5MP (6s 전면)
    /// 저화질 셀카가 피부를 뭉개 줘서 오히려 인기
    var frontSensorLongSide: Double = 1280

    // MARK: 프리셋
    /// iPhone 5s (2013) — 8MP, 차갑고 옅은 색, 좁은 다이나믹 레인지
    static let standard = LookParameters()

    /// 5s 를 더 강하게 — 실내 저조도 5s 느낌 (실제 기종이 아님)
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
        p.hazeAmount = 0.35
        return p
    }

    /// iPhone 6s (2015) — 12MP 로 올라가며 디테일이 늘고, 요즘 "느좋" 으로 꼽히는
    /// 어둡고 따뜻한 저채도 색감. 요즘 아이폰 같은 과한 샤프닝은 없다.
    /// 픽셀이 작아져(1.5 → 1.22µm) 노이즈 알갱이는 더 잘다.
    static var iPhone6s: LookParameters {
        var p = LookParameters()
        p.blackLift = 0.04
        p.highlightRolloff = 0.955
        p.midContrast = 1.06
        p.midGamma = 1.10
        p.targetTemperature = 6750
        p.targetTint = 3
        p.saturation = 0.92
        p.softness = 0.7
        p.sharpenIntensity = 0.45
        p.sharpenRadius = 2.0
        p.hazeAmount = 0.30
        p.grainAmount = 0.45
        p.grainSize = 1.8
        p.shadowGrainBias = 0.85
        p.vignetteIntensity = 0.45
        p.glareAmount = 0.25
        p.sensorLongSide = 4032
        p.frontSensorLongSide = 2576
        return p
    }

    /// 6s 를 더 강하게 — 실내 저조도 6s 느낌 (실제 기종 6s Plus 가 아님)
    /// 노이즈 리덕션이 못 따라가 결이 거칠어지고, 조명 탓에 더 따뜻해진다.
    static var iPhone6sStrong: LookParameters {
        var p = LookParameters.iPhone6s
        p.blackLift = 0.06
        p.highlightRolloff = 0.925
        p.midGamma = 1.15
        p.targetTemperature = 6950
        p.targetTint = 4
        p.saturation = 0.88
        p.softness = 1.0
        p.grainAmount = 0.75
        p.grainSize = 2.0
        p.vignetteIntensity = 0.65
        p.glareAmount = 0.40
        p.hazeAmount = 0.40
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
        p.hazeAmount = 0
        p.frontSensorLongSide = p.sensorLongSide
        return p
    }

    /// 플래시가 터진 사진 — 2010년대 파티·거울 셀카처럼 얼굴은 하얗게 뜨고,
    /// 가장자리는 빛이 못 닿아 빨리 어두워지고, 반짝이는 것에 하이라이트가 번진다.
    /// 플래시는 찍는 순간에만 터지므로 프리뷰에는 보이지 않고 저장본에만 걸린다.
    func withFlash() -> LookParameters {
        guard self != .off else { return self }
        var p = self
        p.highlightRolloff = max(0.85, p.highlightRolloff - 0.02)
        p.midContrast += 0.08
        p.targetTemperature -= 150
        p.vignetteIntensity = min(1.0, p.vignetteIntensity + 0.35)
        p.glareAmount += 0.12
        p.hazeAmount += 0.10
        return p
    }
}

enum LookPreset: String, CaseIterable, Identifiable {
    case standard = "5s"
    case strong   = "5s+"
    case iPhone6s = "6s"
    case iPhone6sStrong = "6s+"
    case off      = "OFF"

    var id: String { rawValue }

    var parameters: LookParameters {
        switch self {
        case .standard: return .standard
        case .strong:   return .strong
        case .iPhone6s: return .iPhone6s
        case .iPhone6sStrong: return .iPhone6sStrong
        case .off:      return .off
        }
    }
}
