// wincap <pid> <out.png>: saves the window of a running process to a PNG,
// even when other windows cover it. scripts/screenshot.sh builds and runs it.
// Needs Screen Recording permission for the terminal that runs it.
// The PNG is at the display's pixel size, so a high_dpi window on a Retina
// display gives a PNG twice the window's size in points.
import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

func windowID(pid: pid_t) -> CGWindowID? {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ((($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double) ?? 0) > 100 }
    return (mine.first?[kCGWindowNumber as String] as? Int).map { CGWindowID($0) }
}

// Pixels per point of the display under the window's centre, or 1 when no display holds it.
func pixelScale(of win: SCWindow, in content: SCShareableContent) -> CGFloat {
    let centre = CGPoint(x: win.frame.midX, y: win.frame.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(centre) }),
          let mode = CGDisplayCopyDisplayMode(display.displayID), mode.width > 0 else { return 1 }
    return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
}

func capture(pid: pid_t, out: URL) async throws {
    guard let id = windowID(pid: pid) else { throw NSError(domain: "wincap", code: 2, userInfo: [NSLocalizedDescriptionKey: "no window for pid \(pid)"]) }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let win = content.windows.first(where: { $0.windowID == id }) else { throw NSError(domain: "wincap", code: 3, userInfo: [NSLocalizedDescriptionKey: "window \(id) not shareable"]) }
    let scale = pixelScale(of: win, in: content)
    let config = SCStreamConfiguration()
    config.width = Int(win.frame.width * scale)
    config.height = Int(win.frame.height * scale)
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: config)
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

_ = NSApplication.shared
let pid = pid_t(CommandLine.arguments[1])!
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let done = DispatchSemaphore(value: 0)
var code: Int32 = 1
Task {
    for attempt in 1...5 {
        do {
            try await capture(pid: pid, out: out)
            code = 0
            break
        } catch {
            FileHandle.standardError.write("wincap attempt \(attempt): \(error.localizedDescription)\n".data(using: .utf8)!)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
    done.signal()
}
done.wait()
exit(code)
