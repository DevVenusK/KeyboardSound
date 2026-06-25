import Foundation

/// RBJ cookbook 기반 2차 밴드패스 필터 (constant skirt gain).
struct BiquadBandpass {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(sampleRate: Double, centerHz: Double, q: Double) {
        let safeQ = max(0.1, q)
        let w0 = 2.0 * Double.pi * centerHz / sampleRate
        let alpha = sin(w0) / (2.0 * safeQ)
        let cosw0 = cos(w0)
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let xd = Double(x)
        let y = b0 * xd + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = xd
        y2 = y1; y1 = y
        return Float(y)
    }
}
