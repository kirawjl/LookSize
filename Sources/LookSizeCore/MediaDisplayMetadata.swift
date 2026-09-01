import Foundation

public enum MediaKind: String, Sendable {
    case image
    case video
}

public struct MediaDisplayMetadata: Equatable, Sendable {
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let frameRate: Double?
    public let isVariableFrameRate: Bool

    public init(
        kind: MediaKind,
        width: Int,
        height: Int,
        frameRate: Double? = nil,
        isVariableFrameRate: Bool = false
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.isVariableFrameRate = isVariableFrameRate
    }
}

public enum MetadataFormatting {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func title(fileName: String, metadata: MediaDisplayMetadata) -> String {
        [fileName, overlayText(metadata: metadata)].joined(separator: " · ")
    }

    public static func overlayText(metadata: MediaDisplayMetadata) -> String {
        var parts = ["\(metadata.width)×\(metadata.height)"]

        if let frameRate = metadata.frameRate, frameRate.isFinite, frameRate > 0 {
            var frameRateText = formatFrameRate(frameRate)
            if metadata.isVariableFrameRate {
                frameRateText += " (VFR)"
            }
            parts.append(frameRateText)
        }

        return parts.joined(separator: " · ")
    }

    public static func formatFrameRate(_ frameRate: Double) -> String {
        guard frameRate.isFinite, frameRate > 0 else { return "" }

        let rounded = frameRate.rounded()
        if abs(frameRate - rounded) < 0.0005 {
            return "\(Int(rounded)) fps"
        }

        var value = String(format: "%.3f", locale: posixLocale, frameRate)
        while value.last == "0" {
            value.removeLast()
        }
        if value.last == "." {
            value.removeLast()
        }
        return "\(value) fps"
    }

    public static func parseRational(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }

        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            let result = numerator / denominator
            return result.isFinite && result > 0 ? result : nil
        }

        if let result = Double(value), result.isFinite, result > 0 {
            return result
        }

        return nil
    }
}
