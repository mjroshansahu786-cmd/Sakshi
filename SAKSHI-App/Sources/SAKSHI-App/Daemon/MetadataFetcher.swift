import AppKit

class MetadataFetcher {
    struct Metadata {
        let appName: String
        let windowTitle: String
        let timestamp: Date
    }

    static func fetchCurrent() -> Metadata {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return Metadata(appName: "Unknown", windowTitle: "", timestamp: Date())
        }
        
        let appName = frontmost.localizedName ?? "Unknown"
        let pid = frontmost.processIdentifier
        let windowTitle = fetchWindowTitle(for: pid) ?? ""
        
        return Metadata(appName: appName, windowTitle: windowTitle, timestamp: Date())
    }
    
    private static func fetchWindowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowElement: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowElement)
        
        guard result == .success, let focusedWindow = focusedWindowElement else { return nil }
        
        var titleElement: CFTypeRef?
        result = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleElement)
        
        guard result == .success, let title = titleElement as? String else { return nil }
        
        return title
    }
}
