import AppKit
import Darwin
import Foundation
import LookSizeCore

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--quicklook-window"] {
    let scanner = QuickLookWindowScanner()
    guard let window = scanner.visibleWindow() else {
        fputs("未检测到可见的 Quick Look 窗口。\n", stderr)
        exit(1)
    }

    let title = window.title ?? "—"
    print(
        "windowID=\(window.windowID) pid=\(window.ownerPID) "
            + "title=\(title) frame=\(NSStringFromRect(window.frame))"
    )
    exit(0)
}

guard arguments.count == 1 else {
    fputs(
        "用法：\n"
            + "  looksize-inspect /path/to/image-or-video\n"
            + "  looksize-inspect --quicklook-window\n",
        stderr
    )
    exit(64)
}

let url = URL(fileURLWithPath: arguments[0]).standardizedFileURL
guard FileManager.default.fileExists(atPath: url.path) else {
    fputs("文件不存在：\(url.path)\n", stderr)
    exit(66)
}

guard MediaMetadataReader.supports(url) else {
    fputs("暂不支持该文件类型：\(url.pathExtension)\n", stderr)
    exit(65)
}

Task {
    let reader = MediaMetadataReader()
    guard let metadata = await reader.metadata(for: url) else {
        fputs("无法读取媒体元数据：\(url.path)\n", stderr)
        exit(1)
    }

    print(MetadataFormatting.title(fileName: url.lastPathComponent, metadata: metadata))
    exit(0)
}

dispatchMain()
