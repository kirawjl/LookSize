import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct MediaMetadataReader: Sendable {
    private static let imageExtensions = Set([
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "heic", "heif",
        "webp", "avif", "bmp", "jp2", "j2k", "psd", "dng", "raw",
        "cr2", "cr3", "nef", "arw", "orf", "rw2"
    ])

    private static let videoExtensions = Set([
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv",
        "mpeg", "mpg", "m2v", "3gp", "3g2", "mts", "m2ts", "ts",
        "vob", "mxf", "dv"
    ])

    public init() {}

    public static func supports(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) || videoExtensions.contains(fileExtension) {
            return true
        }

        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    public func metadata(for url: URL) async -> MediaDisplayMetadata? {
        let fileExtension = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: fileExtension)

        if Self.imageExtensions.contains(fileExtension) || type?.conforms(to: .image) == true {
            return Self.imageMetadata(for: url)
        }

        if Self.videoExtensions.contains(fileExtension)
            || type?.conforms(to: .movie) == true
            || type?.conforms(to: .audiovisualContent) == true {
            if let ffprobeMetadata = await Task.detached(
                priority: .userInitiated,
                operation: { Self.ffprobeMetadata(for: url) }
            ).value {
                return ffprobeMetadata
            }
            return await Self.avFoundationMetadata(for: url)
        }

        return nil
    }

    private static func imageMetadata(for url: URL) -> MediaDisplayMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              var width = integerValue(properties[kCGImagePropertyPixelWidth]),
              var height = integerValue(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            return nil
        }

        // EXIF 5～8 代表画面需要旋转 90°，显示尺寸应交换宽高。
        if let orientation = integerValue(properties[kCGImagePropertyOrientation]),
           (5...8).contains(orientation) {
            swap(&width, &height)
        }

        return MediaDisplayMetadata(kind: .image, width: width, height: height)
    }

    private static func avFoundationMetadata(for url: URL) async -> MediaDisplayMetadata? {
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await videoTrack.load(.naturalSize),
              let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
            return nil
        }

        let transformedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let transformedWidth = Int(abs(transformedRect.width).rounded())
        let transformedHeight = Int(abs(transformedRect.height).rounded())
        let width = transformedWidth > 0 ? transformedWidth : Int(abs(naturalSize.width).rounded())
        let height = transformedHeight > 0 ? transformedHeight : Int(abs(naturalSize.height).rounded())

        guard width > 0, height > 0 else { return nil }

        let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)).map(Double.init)
        let validFrameRate = nominalFrameRate.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }

        return MediaDisplayMetadata(
            kind: .video,
            width: width,
            height: height,
            frameRate: validFrameRate
        )
    }

    private static func ffprobeMetadata(for url: URL) -> MediaDisplayMetadata? {
        guard let executableURL = ffprobeExecutableURL() else { return nil }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries",
            "stream=width,height,avg_frame_rate,r_frame_rate:stream_tags=rotate:stream_side_data=rotation",
            "-of", "json",
            url.path
        ]

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if completion.wait(timeout: .now() + 1.8) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 0.2)
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()

        guard let output = try? JSONDecoder().decode(FFProbeOutput.self, from: data),
              let stream = output.streams.first,
              var width = stream.width,
              var height = stream.height,
              width > 0,
              height > 0 else {
            return nil
        }

        let tagRotation: Double? = stream.tags.flatMap { tags in
            tags["rotate"].flatMap(Double.init)
        }
        let sideDataRotation: Double? = stream.sideDataList?
            .compactMap { $0.rotation }
            .first
        let rotation = tagRotation ?? sideDataRotation ?? 0
        let normalizedRotation = abs(Int(rotation.rounded())) % 180
        if normalizedRotation == 90 {
            swap(&width, &height)
        }

        let averageFrameRate = MetadataFormatting.parseRational(stream.averageFrameRate)
        let realFrameRate = MetadataFormatting.parseRational(stream.realFrameRate)
        let frameRate = averageFrameRate ?? realFrameRate

        var isVariableFrameRate = false
        if let averageFrameRate, let realFrameRate {
            let differenceRatio = abs(averageFrameRate - realFrameRate) / max(averageFrameRate, 1)
            // 仅在差异明显时标记 VFR，避免把 29.97/30 的正常时间基误判为可变帧率。
            isVariableFrameRate = differenceRatio > 0.02
        }

        return MediaDisplayMetadata(
            kind: .video,
            width: width,
            height: height,
            frameRate: frameRate,
            isVariableFrameRate: isVariableFrameRate
        )
    }

    private static func ffprobeExecutableURL() -> URL? {
        var candidates: [String] = []
        if let configuredPath = ProcessInfo.processInfo.environment["LOOKSIZE_FFPROBE"],
           !configuredPath.isEmpty {
            candidates.append(configuredPath)
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ])

        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let value = value as? Int {
            return value
        }
        return nil
    }
}

private struct FFProbeOutput: Decodable {
    let streams: [FFProbeStream]
}

private struct FFProbeStream: Decodable {
    let width: Int?
    let height: Int?
    let averageFrameRate: String?
    let realFrameRate: String?
    let tags: [String: String]?
    let sideDataList: [FFProbeSideData]?

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case averageFrameRate = "avg_frame_rate"
        case realFrameRate = "r_frame_rate"
        case tags
        case sideDataList = "side_data_list"
    }
}

private struct FFProbeSideData: Decodable {
    let rotation: Double?
}
