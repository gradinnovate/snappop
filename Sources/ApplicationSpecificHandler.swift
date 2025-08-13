import Cocoa
import ApplicationServices

// MARK: - Module 3: Application Specific Handler
class ApplicationSpecificHandler {
    
    static func getTextForApplication(_ appName: String, element: AXUIElement, gestureData: FallbackMethodController.GestureData? = nil) -> String? {
        let normalizedAppName = appName.lowercased()
        
        // Check against our enhanced application database
        if let appConfig = getAppConfiguration(for: normalizedAppName) {
            print("ApplicationSpecificHandler: Using specialized handler for \(appName)")
            
            // For applications that use clipboard method, check with FallbackMethodController first
            if appConfig.description.contains("CMD+C") || appConfig.description.contains("fallback") {
                if let gestureData = gestureData {
                    if !FallbackMethodController.shouldUseCmdCFallback(for: appName, gestureData: gestureData) {
                        print("ApplicationSpecificHandler: FallbackMethodController rejected CMD+C for \(appName)")
                        return tryStandardAccessibilityMethod(element)
                    }
                } else {
                    print("ApplicationSpecificHandler: No gesture data for CMD+C decision, trying Accessibility first")
                    if let text = tryStandardAccessibilityMethod(element) {
                        return text
                    }
                }
            }
            
            return appConfig.textExtractionMethod(element)
        }
        
        // Fallback to standard accessibility method
        print("ApplicationSpecificHandler: Using standard handler for \(appName)")
        return tryStandardAccessibilityMethod(element)
    }
    
    private static func getAppConfiguration(for appName: String) -> AppConfiguration? {
        // Enhanced application-specific configurations
        let appConfigurations: [String: AppConfiguration] = [
            // Text Editors (known to have accessibility issues)
            "sublime text": AppConfiguration(
                name: "Sublime Text",
                textExtractionMethod: { _ in return tryClipboardMethod() },
                description: "Uses CMD+C fallback due to limited AX support"
            ),
            
            "visual studio code": AppConfiguration(
                name: "Visual Studio Code",
                textExtractionMethod: { element in 
                    return tryStandardAccessibilityMethod(element) ?? tryClipboardMethod()
                },
                description: "Tries AX first, falls back to CMD+C"
            ),
            
            "xcode": AppConfiguration(
                name: "Xcode",
                textExtractionMethod: { element in
                    return tryStandardAccessibilityMethod(element) ?? tryClipboardMethod()
                },
                description: "Xcode editor text selection"
            ),
            
            // Browsers (usually good AX support but may need special handling)
            "safari": AppConfiguration(
                name: "Safari",
                textExtractionMethod: { element in
                    return tryBrowserSpecificMethod(element)
                },
                description: "Enhanced web content selection"
            ),
            
            "google chrome": AppConfiguration(
                name: "Google Chrome", 
                textExtractionMethod: { element in
                    return tryBrowserSpecificMethod(element)
                },
                description: "Enhanced web content selection"
            ),
            
            "firefox": AppConfiguration(
                name: "Firefox",
                textExtractionMethod: { element in
                    return tryBrowserSpecificMethod(element)
                },
                description: "Enhanced web content selection"
            ),
            
            // Communication Apps (often problematic)
            "wechat": AppConfiguration(
                name: "WeChat",
                textExtractionMethod: { element in
                    return tryStandardAccessibilityMethod(element) ?? tryClipboardMethod()
                },
                description: "Chat message selection with fallback"
            ),
            
            "telegram": AppConfiguration(
                name: "Telegram",
                textExtractionMethod: { element in
                    return tryStandardAccessibilityMethod(element) ?? tryClipboardMethod()
                },
                description: "Chat message selection with fallback"
            ),
            
            "discord": AppConfiguration(
                name: "Discord",
                textExtractionMethod: { element in
                    return tryStandardAccessibilityMethod(element) ?? tryClipboardMethod()
                },
                description: "Chat message selection with fallback"
            )
        ]
        
        // Try exact match first
        if let config = appConfigurations[appName] {
            return config
        }
        
        // Try partial matches for complex app names
        for (key, config) in appConfigurations {
            if appName.contains(key) || key.contains(appName) {
                return config
            }
        }
        
        return nil
    }
    
    private static func tryStandardAccessibilityMethod(_ element: AXUIElement) -> String? {
        // Method 1: Direct selected text
        var selectedText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success {
            if let text = selectedText as? String, !text.isEmpty {
                print("ApplicationSpecificHandler: Got text via AXSelectedText: \(text)")
                return text
            }
        }
        
        // Method 2: Text via selected range
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            if let range = selectedRange, CFGetTypeID(range) == AXValueGetTypeID() {
                let axValue = range as! AXValue
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0 {
                    // Get full text then extract selection
                    var fullText: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullText) == .success {
                        if let text = fullText as? String {
                            let startIndex = max(0, cfRange.location)
                            let endIndex = min(text.count, cfRange.location + cfRange.length)
                            
                            if startIndex < text.count && endIndex <= text.count && startIndex < endIndex {
                                let start = text.index(text.startIndex, offsetBy: startIndex)
                                let end = text.index(text.startIndex, offsetBy: endIndex)
                                let selectedText = String(text[start..<end])
                                if !selectedText.isEmpty {
                                    print("ApplicationSpecificHandler: Got text via range: \(selectedText)")
                                    return selectedText
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func tryBrowserSpecificMethod(_ element: AXUIElement) -> String? {
        // Try standard method first for browsers
        if let text = tryStandardAccessibilityMethod(element) {
            return text
        }
        
        // Browser-specific enhancements could go here
        // For now, fallback to clipboard method
        return tryClipboardMethod()
    }
    
    private static func tryClipboardMethod() -> String? {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
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
        
        // Wait for copy to complete
        usleep(100000) // 0.1 seconds
        
        // Check if clipboard has new content
        let newContent = pasteboard.string(forType: .string)
        
        // Always restore original clipboard content
        if let original = originalContent {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        } else {
            pasteboard.clearContents()
        }
        
        // Return captured content if valid
        if let content = newContent, !content.isEmpty, content != originalContent {
            print("ApplicationSpecificHandler: Got text via clipboard: \(content)")
            return content
        }
        
        return nil
    }
}

struct AppConfiguration {
    let name: String
    let textExtractionMethod: (AXUIElement) -> String?
    let description: String
}