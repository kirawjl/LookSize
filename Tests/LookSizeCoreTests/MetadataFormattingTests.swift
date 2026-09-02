import CoreServices
import Testing
@testable import LookSizeCore

@Test func integerFrameRate() {
    #expect(MetadataFormatting.formatFrameRate(60) == "60 fps")
}

@Test func fractionalFrameRatesKeepUsefulPrecision() {
    #expect(MetadataFormatting.formatFrameRate(29.97002997) == "29.97 fps")
    #expect(MetadataFormatting.formatFrameRate(23.976023976) == "23.976 fps")
    #expect(MetadataFormatting.formatFrameRate(59.94005994) == "59.94 fps")
}

@Test func rationalParsing() {
    let parsed = MetadataFormatting.parseRational("30000/1001") ?? 0
    #expect(abs(parsed - 29.97002997) < 0.000001)
    #expect(MetadataFormatting.parseRational("0/0") == nil)
}

@Test func imageTitle() {
    let metadata = MediaDisplayMetadata(kind: .image, width: 4032, height: 3024)
    #expect(
        MetadataFormatting.title(fileName: "IMG_0001.HEIC", metadata: metadata)
            == "IMG_0001.HEIC · 4032×3024"
    )
    #expect(MetadataFormatting.overlayText(metadata: metadata) == "4032×3024")
}

@Test func finderAutomationPermissionStatusMapping() {
    #expect(FinderAutomationPermission.status(for: noErr) == .authorized)
    #expect(
        FinderAutomationPermission.status(for: OSStatus(errAEEventNotPermitted)) == .denied
    )
    #expect(
        FinderAutomationPermission.status(for: OSStatus(errAEEventWouldRequireUserConsent))
            == .notDetermined
    )
    #expect(
        FinderAutomationPermission.status(for: OSStatus(procNotFound)) == .targetNotRunning
    )
    #expect(FinderAutomationPermission.status(for: -9999) == .unavailable(-9999))
}

@Test func videoTitle() {
    let metadata = MediaDisplayMetadata(
        kind: .video,
        width: 3840,
        height: 2160,
        frameRate: 29.97002997,
        isVariableFrameRate: true
    )
    #expect(
        MetadataFormatting.title(fileName: "A001.mov", metadata: metadata)
            == "A001.mov · 3840×2160 · 29.97 fps (VFR)"
    )
    #expect(
        MetadataFormatting.overlayText(metadata: metadata)
            == "3840×2160 · 29.97 fps (VFR)"
    )
}
