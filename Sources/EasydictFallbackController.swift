import Cocoa
import ApplicationServices
import os.log

// MARK: - Easydict-style Fallback Controller
// Implements the dual fallback strategy from Easydict with smart application detection

class EasydictFallbackController {
    
    // Fallback strategy types
    enum FallbackStrategy {
        case simulatedShortcutFirst    // CMD+C first, then menu bar copy
        case menuBarActionFirst        // Menu bar copy first, then CMD+C
    }
    
    // Text selection methods
    enum SelectionMethod {
        case accessibility
        case simulatedShortcut
        case menuBarAction
    }
    
    // Volume control for CMD+C
    private static var currentAlertVolume: Float = 0.5
    private static var isMutingVolume = false
    
    // Application-specific preferences based on Easydict analysis
    private static let menuBarPreferredApps = [
        "wechat", "telegram", "slack", "discord", "whatsapp",
        "signal", "microsoft teams", "zoom", "messages"
    ]
    
    private static let cmdCPreferredApps = [
        "billfish", "finder", "terminal", "iTerm", "xcode",
        "visual studio code", "sublime text", "vim", "emacs"
    ]
    
    // MARK: - Main Entry Point
    
    static func getSelectedText(
        for applicationName: String,
        element: AXUIElement,
        gestureData: GestureData? = nil
    ) -> String? {
        
        os_log("EasydictFallbackController: Getting selected text for %{public}@", 
               log: .textSelection, type: .info, applicationName)
        
        // Determine optimal strategy based on application
        let strategy = determineOptimalStrategy(for: applicationName)
        
        os_log("Using fallback strategy: %{public}@", log: .textSelection, type: .info, 
               strategy == .simulatedShortcutFirst ? "CMD+C first" : "Menu bar first")
        
        // Execute strategy
        switch strategy {
        case .simulatedShortcutFirst:
            return getSelectedTextBySimulatedShortcutFirst(for: applicationName, element: element)
            
        case .menuBarActionFirst:
            return getSelectedTextByMenuBarActionFirst(for: applicationName, element: element)
        }
    }
    
    // MARK: - Strategy Determination
    
    internal static func determineOptimalStrategy(for applicationName: String) -> FallbackStrategy {
        let appNameLower = applicationName.lowercased()
        
        // Check for menu bar preferred apps
        for preferredApp in menuBarPreferredApps {
            if appNameLower.contains(preferredApp) {
                os_log("App prefers menu bar action: %{public}@", log: .textSelection, type: .debug, applicationName)
                return .menuBarActionFirst
            }
        }
        
        // Check for CMD+C preferred apps
        for preferredApp in cmdCPreferredApps {
            if appNameLower.contains(preferredApp) {
                os_log("App prefers simulated shortcut: %{public}@", log: .textSelection, type: .debug, applicationName)
                return .simulatedShortcutFirst
            }
        }
        
        // Default: Use menu bar first (generally more reliable per Easydict analysis)
        return .menuBarActionFirst
    }
    
    // MARK: - Fallback Strategy A: CMD+C First
    
    internal static func getSelectedTextBySimulatedShortcutFirst(
        for applicationName: String,
        element: AXUIElement
    ) -> String? {
        
        os_log("Attempting simulated shortcut first for %{public}@", log: .textSelection, type: .debug, applicationName)
        
        // Try CMD+C simulation first
        if let text = getSelectedTextBySimulatedShortcut() {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                os_log("Simulated shortcut success: %{public}@", log: .textSelection, type: .info, String(text.prefix(50)))
                return text
            }
        }
        
        os_log("Simulated shortcut failed, trying menu bar action", log: .textSelection, type: .info)
        
        // Fallback to menu bar action copy
        if let text = getSelectedTextByMenuBarAction() {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                os_log("Menu bar action fallback success: %{public}@", log: .textSelection, type: .info, String(text.prefix(50)))
                return text
            }
        }
        
        os_log("Both simulated shortcut and menu bar action failed", log: .textSelection, type: .error)
        return nil
    }
    
    // MARK: - Fallback Strategy B: Menu Bar First
    
    internal static func getSelectedTextByMenuBarActionFirst(
        for applicationName: String,
        element: AXUIElement
    ) -> String? {
        
        os_log("Attempting menu bar action first for %{public}@", log: .textSelection, type: .debug, applicationName)
        
        // Try menu bar action copy first
        if let text = getSelectedTextByMenuBarAction() {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                os_log("Menu bar action success: %{public}@", log: .textSelection, type: .info, String(trimmedText.prefix(50)))
                return trimmedText
            }
        }
        
        os_log("Menu bar action failed, checking for copy menu item", log: .textSelection, type: .info)
        
        // Only use CMD+C fallback if app has no copy menu item (like Easydict logic)
        if !hasCopyMenuItem() {
            os_log("No copy menu item found, trying simulated shortcut", log: .textSelection, type: .info)
            
            if let text = getSelectedTextBySimulatedShortcut() {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    os_log("Simulated shortcut fallback success: %{public}@", log: .textSelection, type: .info, String(text.prefix(50)))
                    return text
                }
            }
        } else {
            os_log("App has copy menu item but menu bar action failed - not using CMD+C", log: .textSelection, type: .info)
        }
        
        os_log("All fallback methods failed for %{public}@", log: .textSelection, type: .error, applicationName)
        return nil
    }
    
    // MARK: - Menu Bar Action Copy Implementation
    
    private static func getSelectedTextByMenuBarAction() -> String? {
        os_log("Getting selected text by menu bar action", log: .textSelection, type: .debug)
        
        guard let copyMenuItem = findCopyMenuItem() else {
            os_log("No copy menu item found", log: .textSelection, type: .debug)
            return nil
        }
        
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Clear clipboard to detect new content
        pasteboard.clearContents()
        
        // Perform menu action
        copyMenuItem.performAction()
        
        // Small delay for menu action to complete
        usleep(50000) // 50ms
        
        // Check for new clipboard content
        var newContent: String?
        let maxRetries = 5
        var retries = 0
        
        while retries < maxRetries {
            if pasteboard.changeCount > originalChangeCount {
                newContent = pasteboard.string(forType: .string)
                if let content = newContent, !content.isEmpty, content != originalContent {
                    break
                }
            }
            usleep(10000) // 10ms
            retries += 1
        }
        
        // Restore original clipboard content
        pasteboard.clearContents()
        if let original = originalContent {
            pasteboard.setString(original, forType: .string)
        }
        
        return newContent
    }
    
    // MARK: - Simulated Shortcut Implementation (Enhanced)
    
    private static func getSelectedTextBySimulatedShortcut() -> String? {
        os_log("Getting selected text by simulated shortcut with volume muting", log: .textSelection, type: .debug)
        
        // Mute system alert volume to avoid beeps
        muteSystemAlertVolume()
        
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Clear clipboard
        pasteboard.clearContents()
        
        // Simulate CMD+C
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C key
        let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        keyDownEvent?.flags = .maskCommand
        keyUpEvent?.flags = .maskCommand
        
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
        
        // Wait for clipboard to update
        var newContent: String?
        let maxRetries = 10
        var retries = 0
        
        while retries < maxRetries {
            usleep(10000) // 10ms
            
            if pasteboard.changeCount > originalChangeCount {
                newContent = pasteboard.string(forType: .string)
                if let content = newContent, !content.isEmpty, content != originalContent {
                    break
                }
            }
            retries += 1
        }
        
        // Always restore original clipboard content immediately
        pasteboard.clearContents()
        if let original = originalContent {
            pasteboard.setString(original, forType: .string)
        }
        
        // Schedule volume restoration
        restoreSystemAlertVolumeAfterDelay()
        
        return newContent
    }
    
    // MARK: - Menu Item Detection
    
    private static func hasCopyMenuItem() -> Bool {
        return findCopyMenuItem() != nil
    }
    
    private static func findCopyMenuItem() -> NSMenuItem? {
        guard NSWorkspace.shared.frontmostApplication != nil else {
            return nil
        }
        
        // Get the main menu of the frontmost application
        guard let mainMenu = NSApplication.shared.mainMenu ?? NSApp.mainMenu else {
            os_log("No main menu found", log: .textSelection, type: .debug)
            return nil
        }
        
        // Search through menu structure for Copy item
        return searchMenuForCopyItem(mainMenu)
    }
    
    private static func searchMenuForCopyItem(_ menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            // Check if this is a Copy item
            if isCopyMenuItem(item) {
                return item
            }
            
            // Recursively search submenus
            if let submenu = item.submenu {
                if let copyItem = searchMenuForCopyItem(submenu) {
                    return copyItem
                }
            }
        }
        return nil
    }
    
    private static func isCopyMenuItem(_ item: NSMenuItem) -> Bool {
        let title = item.title.lowercased()
        let copyTitles = ["copy", "复制", "複製", "コピー", "copiar", "copier", "kopieren"]
        
        // Check title match
        for copyTitle in copyTitles {
            if title.contains(copyTitle) {
                // Verify it's not "Copy Link" or similar
                let excludeWords = ["link", "url", "address", "path", "as", "to"]
                let hasExcludeWord = excludeWords.contains { title.contains($0) }
                
                if !hasExcludeWord {
                    // Check if item is enabled and has action
                    if item.isEnabled && (item.action != nil || item.target != nil) {
                        return true
                    }
                }
            }
        }
        
        // Check for standard Copy command (⌘C)
        if item.keyEquivalent == "c" && item.keyEquivalentModifierMask.contains(.command) {
            return item.isEnabled
        }
        
        return false
    }
    
    // MARK: - Volume Control (Basic Implementation)
    
    private static func muteSystemAlertVolume() {
        guard !isMutingVolume else { return }
        
        isMutingVolume = true
        
        // Get current alert volume (simplified - in real implementation would use AudioServicesGetProperty)
        // This is a placeholder for the volume muting logic
        os_log("Muting system alert volume", log: .textSelection, type: .debug)
        
        // In a full implementation, this would:
        // 1. Get current alert volume using AudioServices APIs
        // 2. Set alert volume to 0
        // 3. Store original volume for restoration
    }
    
    private static func restoreSystemAlertVolumeAfterDelay() {
        // Delay restoration to avoid immediate beeps
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            restoreSystemAlertVolume()
        }
    }
    
    private static func restoreSystemAlertVolume() {
        guard isMutingVolume else { return }
        
        os_log("Restoring system alert volume", log: .textSelection, type: .debug)
        
        // In a full implementation, this would restore the original alert volume
        
        isMutingVolume = false
    }
    
    // MARK: - Utility Methods
    
    static func shouldUseFallback(for applicationName: String, gestureData: GestureData? = nil) -> Bool {
        let appNameLower = applicationName.lowercased()
        
        // Always allow fallback for known problematic applications
        let alwaysFallbackApps = ["sublime text", "visual studio code", "terminal", "billfish", "finder"]
        
        for app in alwaysFallbackApps {
            if appNameLower.contains(app) {
                return true
            }
        }
        
        // For other apps, use gesture-based decision
        if let gesture = gestureData {
            // Allow fallback for reasonable text selection gestures
            let isReasonableGesture = gesture.distance > 10 && gesture.distance < 500 && gesture.duration < 3.0
            return isReasonableGesture
        }
        
        // Default: allow fallback
        return true
    }
}

// MARK: - Enhanced NSMenuItem Extension

private extension NSMenuItem {
    func performAction() {
        os_log("Performing menu action: %{public}@", log: .textSelection, type: .debug, self.title)
        
        // Try different methods to perform the menu action
        if let target = self.target, let action = self.action {
            // Method 1: Direct action
            _ = target.perform(action, with: self)
        } else if self.isEnabled, let action = self.action {
            // Method 2: Send action up responder chain
            NSApp.sendAction(action, to: self.target, from: self)
        }
        
        // Small delay to ensure action completes
        usleep(20000) // 20ms
    }
}