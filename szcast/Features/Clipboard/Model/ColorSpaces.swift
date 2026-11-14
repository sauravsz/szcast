import Foundation

extension ColorValue {
    /// Oklab is defined on light, not on the gamma-encoded numbers a hex triplet carries.
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private var linearComponents: (r: Double, g: Double, b: Double) {
        (Self.linear(red), Self.linear(green), Self.linear(blue))
    }

    /// Oklab: the same idea as Lab, fitted so equal steps look equal. `l` is 0…1.
    private var oklab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = linearComponents
        let long = Self.cubeRoot(0.4122215 * r + 0.5363325 * g + 0.0514460 * b)
        let medium = Self.cubeRoot(0.2119035 * r + 0.6806995 * g + 0.1073970 * b)
        let short = Self.cubeRoot(0.0883025 * r + 0.2817188 * g + 0.6299787 * b)
        return (
            0.2104543 * long + 0.7936178 * medium - 0.0040720 * short,
            1.9779985 * long - 2.4285922 * medium + 0.4505937 * short,
            0.0259040 * long + 0.7827718 * medium - 0.8086758 * short
        )
    }

    var oklch: (l: Double, c: Double, h: Double) {
        let oklab = oklab
        return (
            oklab.l, (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot(),
            Self.hueDegrees(oklab.a, oklab.b)
        )
    }

    /// CIELAB (D65 illuminant, 2° observer)
    var lab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = linearComponents
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.00000
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856451679 ? pow(t, 1.0 / 3.0) : (7.787037037 * t + 16.0 / 116.0)
        }

        let fx = f(x)
        let fy = f(y)
        let fz = f(z)

        let l = max(0, 116.0 * fy - 16.0)
        let a = 500.0 * (fx - fy)
        let bVal = 200.0 * (fy - fz)
        return (l, a, bVal)
    }

    /// `pow` is undefined for a negative base at a fractional exponent, and a channel can be one.
    private static func cubeRoot(_ value: Double) -> Double {
        value < 0 ? -pow(-value, 1.0 / 3) : pow(value, 1.0 / 3)
    }

    /// Zero for a neutral: `atan2` over two rounding errors would still name a direction.
    private static func hueDegrees(_ a: Double, _ b: Double) -> Double {
        guard abs(a) > 1e-6 || abs(b) > 1e-6 else { return 0 }
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The inverse of `oklch`: a colour picker states its swatch in the space, not in hex.
    init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let long = Self.cubed(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let medium = Self.cubed(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let short = Self.cubed(lightness - 0.0894841775 * a - 1.2914855480 * b)
        self.init(
            red: Self.gamma(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: Self.gamma(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: Self.gamma(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short),
            alpha: alpha)
    }

    /// Inverse CIELAB to sRGB
    init(cielabL l: Double, a: Double, b: Double, alpha: Double = 1) {
        let fy = (l + 16.0) / 116.0
        let fx = a / 500.0 + fy
        let fz = fy - b / 200.0

        func invF(_ t: Double) -> Double {
            let t3 = t * t * t
            return t3 > 0.008856451679 ? t3 : (t - 16.0 / 116.0) / 7.787037037
        }

        let xr = invF(fx)
        let yr = invF(fy)
        let zr = invF(fz)

        let x = xr * 0.95047
        let y = yr * 1.00000
        let z = zr * 1.08883

        let rLin = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let gLin = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let bLin = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z

        self.init(
            red: Self.gamma(rLin),
            green: Self.gamma(gLin),
            blue: Self.gamma(bLin),
            alpha: alpha)
    }

    private static func cubed(_ value: Double) -> Double { value * value * value }

    /// The inverse of `linear`; a channel below the split can be negative, and `pow` answers NaN.
    private static func gamma(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}
