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
    /// 35mm 필름 색 (FilmColor) 을 얼마나 섞을지 — 0 = 없음, 1 = 100%
    var filmColor: Double = 0

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
    /// 할레이션 — 밝은 곳 가장자리의 붉은 번짐 (필름 뒷면 반사). 0 = 없음
    var halation: Double = 0

    // MARK: 5-1. 심도·거리감 (DepthEffect — 저장본에만)
    /// 사람 뒤 배경 흐림 반경 (px @3264). 0 = 없음
    var depthBlur: Double = 0
    /// 배경을 밝은 공기 쪽으로 옅게 — 먼 곳이 뿌옇게 보이는 공기 원근. 0 = 없음
    var depthHaze: Double = 0

    // MARK: 6. 센서
    /// 저장 해상도의 긴 변 — 3264 = 8MP (5s), 4032 = 12MP (6s)
    var sensorLongSide: Double = 3264
    /// 후면 35mm 환산 초점거리 — 29 = iPhone 5s~6s, 35 = Leica minilux zoom 광각 끝
    /// 요즘 메인 렌즈(24~26mm)의 가운데를 잘라 이 화각에 맞춘다 (LegacyLens)
    var focalLength: Double = 29
    /// 셀카 저장 해상도의 긴 변 — 1280 = 1.2MP (5s 전면), 2576 = 5MP (6s 전면)
    /// 저화질 셀카가 피부를 뭉개 줘서 오히려 인기
    var frontSensorLongSide: Double = 1280

    // MARK: 프리셋
    /// iPhone 5s (2013) — 8MP, 차갑고 옅은 색, 좁은 다이나믹 레인지
    static let standard = LookParameters()

    /// 35mm 컬러 필름 — 여름 해변 필름 사진 레퍼런스 (Leica minilux zoom 으로 찍은 사진).
    /// 진한 빨강·노랑, 올리브 초록, 청록 파랑, 황금빛 피부, 크림빛 하이라이트,
    /// 사람 뒤 배경은 살짝 흐리고 옅게 (심도·거리감), 고운 필름 그레인, 은은한 할레이션.
    /// - 화각: minilux zoom 의 광각 끝 35mm — 폰보다 좁고 원근 왜곡이 적어 거리감이 자연스럽다
    /// - 심도: f/3.5~6.5 로 어두운 똑딱이 렌즈라 배경이 크게 녹지 않는다 → 흐림은 약하게
    /// - 해상도: 필름 현상소 스캔(약 3000px) 급 8MP. 35mm 로 잘라도 확대가 생기지 않는다
    static var film: LookParameters {
        var p = LookParameters()
        p.blackLift = 0.035
        p.highlightRolloff = 0.965
        p.midContrast = 1.08
        p.midGamma = 0.95
        p.targetTemperature = 6900
        p.targetTint = 2
        p.saturation = 1.02
        p.filmColor = 1.0
        p.softness = 0.5
        p.sharpenIntensity = 0.2
        p.sharpenRadius = 2.0
        p.hazeAmount = 0.15
        p.grainAmount = 0.35
        p.grainSize = 1.7
        p.shadowGrainBias = 0.5
        p.vignetteIntensity = 0.30
        p.vignetteRadius = 1.6
        p.glareAmount = 0.18
        p.glareRadius = 12
        p.halation = 0.25
        p.depthBlur = 12
        p.depthHaze = 0.10
        p.focalLength = 35
        p.sensorLongSide = 3264
        p.frontSensorLongSide = 3264
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

    /// 플래시가 터진 사진 — 2010년대 파티·거울 셀카처럼 얼굴은 하얗게 뜨고,
    /// 가장자리는 빛이 못 닿아 빨리 어두워지고, 반짝이는 것에 하이라이트가 번진다.
    /// 플래시는 찍는 순간에만 터지므로 프리뷰에는 보이지 않고 저장본에만 걸린다.
    func withFlash() -> LookParameters {
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

/// 룩은 세 가지만 — 필름 카메라 하나, 옛날 아이폰 둘 (차가운 5s / 따뜻한 6s)
enum LookPreset: String, CaseIterable, Identifiable {
    case film     = "FILM"
    case standard = "5s"
    case iPhone6s = "6s"

    var id: String { rawValue }

    var parameters: LookParameters {
        switch self {
        case .film:     return .film
        case .standard: return .standard
        case .iPhone6s: return .iPhone6s
        }
    }
}
