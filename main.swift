import Cocoa
import ApplicationServices
import os.log

// MARK: - Logging System for Production Release
// Usage: os_log("message", log: .category, type: .level)
// Types: .debug (dev only), .info (general info), .default (important), .error (errors), .fault (critical)
// View logs: Console.app > search for "SnapPop" or use: log show --predicate 'subsystem == "com.gradinnovate.snappop"'
extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.gradinnovate.snappop"
    
    static let textSelection = OSLog(subsystem: subsystem, category: "TextSelection")
    static let popup = OSLog(subsystem: subsystem, category: "Popup")
    static let accessibility = OSLog(subsystem: subsystem, category: "Accessibility")
    static let validation = OSLog(subsystem: subsystem, category: "Validation")
    static let lifecycle = OSLog(subsystem: subsystem, category: "Lifecycle")
}

// MARK: - Module 1: Text Frame Validator
class TextFrameValidator {
    static func validateMousePositionInTextFrame(_ element: AXUIElement, mouseDownLocation: CGPoint?, currentMouseLocation: CGPoint?) -> Bool {
        guard let mouseDown = mouseDownLocation, let currentMouse = currentMouseLocation else {
            os_log("Missing mouse position data, skipping validation", log: .validation, type: .info)
            return true // Fallback to original behavior if no mouse data
        }
        
        // Try to get the text selection frame
        guard let textFrame = getTextSelectionFrame(from: element) else {
            print("TextFrameValidator: Could not get text frame, allowing selection")
            return true // Fallback to original behavior if frame unavailable
        }
        
        // Expand frame by 40px (like Easydict) to handle imprecise bounds
        let expandedFrame = textFrame.insetBy(dx: -40, dy: -40)
        
        let mouseDownInFrame = expandedFrame.contains(mouseDown)
        let currentMouseInFrame = expandedFrame.contains(currentMouse)
        
        print("TextFrameValidator: Frame=\(textFrame), Expanded=\(expandedFrame)")
        print("TextFrameValidator: MouseDown(\(mouseDown)) in frame: \(mouseDownInFrame)")
        print("TextFrameValidator: CurrentMouse(\(currentMouse)) in frame: \(currentMouseInFrame)")
        
        // Both start and end positions should be within the text area
        return mouseDownInFrame && currentMouseInFrame
    }
    
    static func getTextSelectionFrame(from element: AXUIElement) -> CGRect? {
        // Method 1: Try to get bounds for selected text range
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
           let range = selectedRange {
            
            var textFrame: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range,
                &textFrame
            )
            
            if result == .success, let frame = textFrame {
                if CFGetTypeID(frame) == AXValueGetTypeID() {
                    let axValue = frame as! AXValue
                    var rect = CGRect.zero
                    if AXValueGetValue(axValue, .cgRect, &rect) {
                        debugPrint("TextFrameValidator: Got text frame via bounds for range: \(rect)")
                        return rect
                    }
                }
            }
        }
        
        // Method 2: Fallback to element's general frame  
        var elementFrame: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &elementFrame) == .success,
           let frame = elementFrame {
            if CFGetTypeID(frame) == AXValueGetTypeID() {
                let axValue = frame as! AXValue
                var size = CGSize.zero
                if AXValueGetValue(axValue, .cgSize, &size) {
                    // Try to get position as well
                    var positionRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
                       let posRef = positionRef, CFGetTypeID(posRef) == AXValueGetTypeID() {
                        let posValue = posRef as! AXValue
                        var position = CGPoint.zero
                        if AXValueGetValue(posValue, .cgPoint, &position) {
                            let rect = CGRect(origin: position, size: size)
                            debugPrint("TextFrameValidator: Got element frame as fallback: \(rect)")
                            return rect
                        }
                    }
                }
            }
        }
        
        os_log("Could not get any frame information", log: .validation, type: .debug)
        return nil
    }
}

// MARK: - Module 2: Popup Position Calculator
class PopupPositionCalculator {
    static func calculateSmartPosition(
        originalPosition: NSPoint,
        mouseLocation: CGPoint,
        mouseDownLocation: CGPoint?,
        windowSize: NSSize,
        selectedText: String
    ) -> NSPoint {
        
        // Detect text selection direction if we have mouse down data
        let selectionDirection = detectSelectionDirection(
            mouseDown: mouseDownLocation,
            mouseUp: mouseLocation
        )
        
        // Calculate enhanced position based on selection direction
        var smartPosition = calculateDirectionalPosition(
            mouseLocation: mouseLocation,
            direction: selectionDirection,
            windowSize: windowSize
        )
        
        // Apply screen boundary handling with safety margins (like Easydict)
        smartPosition = applySafetyConstraints(
            position: smartPosition,
            windowSize: windowSize,
            safetyMargin: 50
        )
        
        print("PopupPositionCalculator: Original=\(originalPosition), Smart=\(smartPosition), Direction=\(selectionDirection)")
        
        // Return smart position if valid, otherwise fallback to original
        return isValidPosition(smartPosition, windowSize: windowSize) ? smartPosition : originalPosition
    }
    
    private static func detectSelectionDirection(mouseDown: CGPoint?, mouseUp: CGPoint) -> SelectionDirection {
        guard let mouseDown = mouseDown else {
            return .unknown
        }
        
        let deltaX = mouseUp.x - mouseDown.x
        let deltaY = mouseUp.y - mouseDown.y
        
        // Determine primary direction based on larger movement
        if abs(deltaX) > abs(deltaY) {
            return deltaX > 0 ? .leftToRight : .rightToLeft
        } else {
            return deltaY > 0 ? .topToBottom : .bottomToTop
        }
    }
    
    private static func calculateDirectionalPosition(
        mouseLocation: CGPoint,
        direction: SelectionDirection,
        windowSize: NSSize
    ) -> NSPoint {
        
        let offset: CGFloat = 20 // Distance from selection
        
        switch direction {
        case .leftToRight:
            // Position to the right of selection end
            return NSPoint(x: mouseLocation.x + offset, y: mouseLocation.y - windowSize.height - offset)
            
        case .rightToLeft:
            // Position to the left of selection end
            return NSPoint(x: mouseLocation.x - windowSize.width - offset, y: mouseLocation.y - windowSize.height - offset)
            
        case .topToBottom:
            // Position below selection end
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y - windowSize.height - offset)
            
        case .bottomToTop:
            // Position above selection end
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y + offset)
            
        case .unknown:
            // Fallback to centered position slightly below
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y - windowSize.height - offset)
        }
    }
    
    private static func applySafetyConstraints(
        position: NSPoint,
        windowSize: NSSize,
        safetyMargin: CGFloat
    ) -> NSPoint {
        
        guard let screen = NSScreen.main else {
            return position
        }
        
        let screenFrame = screen.visibleFrame
        let safeFrame = screenFrame.insetBy(dx: safetyMargin, dy: safetyMargin)
        
        var safePosition = position
        
        // Horizontal constraints
        safePosition.x = max(safeFrame.minX, min(safePosition.x, safeFrame.maxX - windowSize.width))
        
        // Vertical constraints  
        safePosition.y = max(safeFrame.minY, min(safePosition.y, safeFrame.maxY - windowSize.height))
        
        return safePosition
    }
    
    private static func isValidPosition(_ position: NSPoint, windowSize: NSSize) -> Bool {
        guard let screen = NSScreen.main else {
            return false
        }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = NSRect(origin: position, size: windowSize)
        
        return screenFrame.contains(windowFrame)
    }
}

enum SelectionDirection {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
    case unknown
}

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

// MARK: - Module 4: Enhanced Event Validator
class EnhancedEventValidator {
    
    static func validateSelectionGesture(
        mouseDown: CGPoint,
        mouseUp: CGPoint,
        duration: CFTimeInterval,
        distance: Double
    ) -> ValidationResult {
        
        // Basic gesture classification
        let gestureType = classifyGesture(distance: distance, duration: duration)
        
        // Validate based on gesture type
        switch gestureType {
        case .drag:
            return validateDragGesture(mouseDown: mouseDown, mouseUp: mouseUp, distance: distance)
            
        case .longPress:
            return validateLongPressGesture(duration: duration)
            
        case .click:
            return ValidationResult(isValid: false, reason: "Simple click - no text selection expected")
            
        case .unknown:
            return ValidationResult(isValid: true, reason: "Unknown gesture pattern - allowing with caution")
        }
    }
    
    private static func classifyGesture(distance: Double, duration: CFTimeInterval) -> GestureType {
        let isSignificantMovement = distance > 5
        let isLongDuration = duration > 0.3
        
        if isSignificantMovement && isLongDuration {
            return .drag
        } else if isSignificantMovement && !isLongDuration {
            return .drag  // Quick drag
        } else if !isSignificantMovement && isLongDuration {
            return .longPress
        } else {
            return .click
        }
    }
    
    private static func validateDragGesture(mouseDown: CGPoint, mouseUp: CGPoint, distance: Double) -> ValidationResult {
        // Enhanced drag validation
        
        // 1. Minimum distance threshold (more generous than original)
        if distance < 3 {
            return ValidationResult(isValid: false, reason: "Drag distance too small: \(distance)")
        }
        
        // 2. Detect window resize operations (usually start near screen edges or window borders)
        if isLikelyWindowResizeOperation(mouseDown: mouseDown, distance: distance) {
            return ValidationResult(isValid: false, reason: "Likely window resize operation")
        }
        
        // 3. Maximum reasonable distance for text selection
        if distance > 800 {
            return ValidationResult(isValid: false, reason: "Drag distance too large for text selection: \(distance)")
        }
        
        // 4. Direction analysis - prefer horizontal/vertical drags (common for text selection)
        let deltaX = abs(mouseUp.x - mouseDown.x)
        let deltaY = abs(mouseUp.y - mouseDown.y)
        let aspectRatio = max(deltaX, deltaY) / max(min(deltaX, deltaY), 1)
        
        if aspectRatio > 8 {
            // Very linear drag - likely text selection
            return ValidationResult(isValid: true, reason: "Linear drag pattern detected (ratio: \(aspectRatio))")
        } else if aspectRatio > 2.5 {
            // Somewhat linear - probably text selection
            return ValidationResult(isValid: true, reason: "Semi-linear drag pattern detected (ratio: \(aspectRatio))")
        } else {
            // More diagonal - likely window operation, be more restrictive
            if distance > 300 {
                return ValidationResult(isValid: false, reason: "Large diagonal drag - likely window operation: \(distance)px")
            } else if distance > 150 {
                // Allow medium diagonal drags - could be text selection across multiple lines
                return ValidationResult(isValid: true, reason: "Medium diagonal drag - allowing for multi-line text selection: \(distance)px")
            } else {
                return ValidationResult(isValid: true, reason: "Small diagonal drag - allowing: \(distance)px")
            }
        }
    }
    
    private static func isLikelyWindowResizeOperation(mouseDown: CGPoint, distance: Double) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let screenFrame = screen.visibleFrame
        let edgeThreshold: CGFloat = 50 // Distance from screen edge to consider "near edge"
        
        // Check if drag started near screen edges (common for window resizing)
        let nearLeftEdge = mouseDown.x < screenFrame.minX + edgeThreshold
        let nearRightEdge = mouseDown.x > screenFrame.maxX - edgeThreshold
        let nearTopEdge = mouseDown.y > screenFrame.maxY - edgeThreshold
        let nearBottomEdge = mouseDown.y < screenFrame.minY + edgeThreshold
        
        let nearScreenEdge = nearLeftEdge || nearRightEdge || nearTopEdge || nearBottomEdge
        
        // If starting near screen edge with significant movement, likely window resize
        if nearScreenEdge && distance > 100 {
            return true
        }
        
        // Very large drags are usually window operations
        if distance > 500 {
            return true
        }
        
        return false
    }
    
    private static func validateLongPressGesture(duration: CFTimeInterval) -> ValidationResult {
        // Enhanced long press validation
        
        if duration < 0.25 {
            return ValidationResult(isValid: false, reason: "Duration too short for long press: \(duration)")
        }
        
        if duration > 5.0 {
            return ValidationResult(isValid: false, reason: "Duration too long - likely not intentional: \(duration)")
        }
        
        return ValidationResult(isValid: true, reason: "Valid long press gesture: \(duration)s")
    }
}

enum GestureType {
    case drag
    case longPress
    case click
    case unknown
}

struct ValidationResult {
    let isValid: Bool
    let reason: String
}

// MARK: - Module 6: Fallback Method Controller
class FallbackMethodController {
    
    struct GestureData {
        let mouseDown: CGPoint
        let mouseUp: CGPoint
        let duration: TimeInterval
        let distance: Double
    }
    
    static func shouldUseCmdCFallback(for appName: String, gestureData: GestureData?) -> Bool {
        let normalizedAppName = appName.lowercased()
        
        // Chrome-specific restrictions
        if normalizedAppName.contains("chrome") {
            return shouldUseCmdCForChrome(gestureData: gestureData)
        }
        
        // Safari-specific restrictions
        if normalizedAppName.contains("safari") {
            return shouldUseCmdCForSafari(gestureData: gestureData)
        }
        
        // Firefox-specific restrictions
        if normalizedAppName.contains("firefox") {
            return shouldUseCmdCForFirefox(gestureData: gestureData)
        }
        
        // Default: allow CMD+C for other applications
        return true
    }
    
    private static func shouldUseCmdCForChrome(gestureData: GestureData?) -> Bool {
        print("Chrome detected - evaluating CMD+C fallback necessity")
        
        guard let gesture = gestureData else {
            print("Chrome: No gesture data available - rejecting CMD+C")
            return false
        }
        
        // Chrome requires clear text selection gestures
        let hasSignificantDrag = gesture.distance >= 10
        let hasLongHold = gesture.duration >= 0.5
        
        if !hasSignificantDrag && !hasLongHold {
            print("Chrome: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Chrome: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
    
    private static func shouldUseCmdCForSafari(gestureData: GestureData?) -> Bool {
        print("Safari detected - evaluating CMD+C fallback necessity")
        
        guard let gesture = gestureData else {
            print("Safari: No gesture data available - rejecting CMD+C")
            return false
        }
        
        // Safari is slightly more lenient than Chrome
        let hasMinimalDrag = gesture.distance >= 5
        let hasMinimalHold = gesture.duration >= 0.3
        
        if !hasMinimalDrag && !hasMinimalHold {
            print("Safari: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Safari: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
    
    private static func shouldUseCmdCForFirefox(gestureData: GestureData?) -> Bool {
        print("Firefox detected - evaluating CMD+C fallback necessity")
        
        // Firefox generally has better accessibility support, be more restrictive
        guard let gesture = gestureData else {
            print("Firefox: No gesture data available - rejecting CMD+C")
            return false
        }
        
        let hasSignificantDrag = gesture.distance >= 15
        let hasLongHold = gesture.duration >= 0.6
        
        if !hasSignificantDrag && !hasLongHold {
            print("Firefox: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Firefox: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
}

// MARK: - Module 5: Popup Dismissal Manager
class PopupDismissalManager {
    weak var popupWindow: PopupMenuWindow?
    private var scrollMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var keyMonitor: Any?
    private var isCleanedUp: Bool = false
    private var isDismissing: Bool = false // Prevent double cleanup
    private var lastMouseMoveCheck: CFTimeInterval = 0 // Rate limiting for mouse move checks
    
    init(popupWindow: PopupMenuWindow) {
        self.popupWindow = popupWindow
        setupDismissalMonitoring()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupDismissalMonitoring() {
        setupScrollWheelMonitoring()
        setupMouseMoveMonitoring()
        setupKeyboardMonitoring()
    }
    
    private func setupScrollWheelMonitoring() {
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let window = self.popupWindow, window.isVisible else { return }
            
            let scrollDistance = abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX)
            
            if scrollDistance > 80 { // Easydict's threshold
                print("PopupDismissalManager: Scroll detected (\(scrollDistance)), dismissing popup")
                self.dismissPopup()
            }
        }
    }
    
    private func setupMouseMoveMonitoring() {
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self, let window = self.popupWindow, window.isVisible else { return }
            
            // Rate limiting: only check every 50ms to prevent excessive calls during fast mouse movement
            let currentTime = CFAbsoluteTimeGetCurrent()
            if currentTime - self.lastMouseMoveCheck < 0.05 {
                return
            }
            self.lastMouseMoveCheck = currentTime
            
            let mouseLocation = NSEvent.mouseLocation
            let windowCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let distance = sqrt(pow(mouseLocation.x - windowCenter.x, 2) + pow(mouseLocation.y - windowCenter.y, 2))
            
            if distance > 120 { // Easydict's 120px radius
                print("PopupDismissalManager: Mouse moved outside radius (\(distance)px), dismissing popup")
                self.dismissPopup()
            }
        }
    }
    
    private func setupKeyboardMonitoring() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.popupWindow, window.isVisible else { return }
            
            // Dismiss on any keyboard activity (except during CMD+C operations)
            print("PopupDismissalManager: Keyboard activity detected, dismissing popup")
            self.dismissPopup()
        }
    }
    
    private func dismissPopup() {
        // Prevent multiple simultaneous dismissal attempts
        guard !isDismissing else {
            debugPrint("🔧 DEBUG: Dismissal already in progress, skipping...")
            return
        }
        
        isDismissing = true
        debugPrint("🔧 DEBUG: Starting dismissal process")
        
        DispatchQueue.main.async { [weak self] in
            self?.popupWindow?.closeAndNotify()
        }
    }
    
    func cleanup() {
        debugPrint("🔧 DEBUG: PopupDismissalManager cleanup called, isCleanedUp: \(isCleanedUp)")
        
        // Prevent double cleanup
        guard !isCleanedUp else {
            debugPrint("🔧 DEBUG: Already cleaned up, skipping...")
            return
        }
        
        isCleanedUp = true
        isDismissing = false // Reset dismissal flag
        
        // CRITICAL: Clear window reference FIRST to prevent access during cleanup
        popupWindow = nil
        
        // Remove monitors with additional safety checks
        if let monitor = scrollMonitor {
            debugPrint("🔧 DEBUG: Removing scroll monitor")
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        
        if let monitor = mouseMoveMonitor {
            debugPrint("🔧 DEBUG: Removing mouse move monitor")
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
        
        if let monitor = keyMonitor {
            debugPrint("🔧 DEBUG: Removing key monitor")
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        
        debugPrint("🔧 DEBUG: PopupDismissalManager cleanup completed")
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popupWindow: NSWindow?
    var eventTap: CFMachPort?
    var mouseDownLocation: CGPoint?
    var mouseDownTime: CFTimeInterval = 0
    
    // Enhanced detection for double-click and improved false positive prevention
    private var lastClickTime: CFTimeInterval = 0
    private var lastClickLocation: CGPoint = CGPoint.zero
    private var clickCount: Int = 0
    
    // Segfault fix: Prevent multiple concurrent popup creations
    private var isCreatingPopup: Bool = false
    private let popupCreationQueue = DispatchQueue(label: "com.snappop.popup", qos: .userInteractive)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !checkAccessibilityPermissions() {
            showAccessibilityAlert()
            return
        }
        
        setupStatusItem()
        setupTextSelectionMonitoring()
    }
    
    func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Please go to System Preferences > Security & Privacy > Privacy > Accessibility and add this application."
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApplication.shared.terminate(nil)
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "SnapPop")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }
    
    @objc func statusItemClicked() {
        // Create a simple menu instead of terminating the app
        let menu = NSMenu()
        
        let aboutItem = NSMenuItem(title: "About SnapPop", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit SnapPop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Show the menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SnapPop"
        alert.informativeText = "A contextual quick menu that appears when you select text.\n\nVersion 1.1\nBuilt with ❤️ for macOS"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func setupTextSelectionMonitoring() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                if type == .leftMouseDown {
                    appDelegate.handleMouseDown(event: event)
                } else if type == .leftMouseUp {
                    appDelegate.handleMouseUp(event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    func handleMouseDown(event: CGEvent) {
        mouseDownLocation = event.location
        mouseDownTime = CFAbsoluteTimeGetCurrent()
        debugPrint("Mouse down at location: \(mouseDownLocation!)")
    }
    
    func handleMouseUp(event: CGEvent) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let mouseUpLocation = event.location
        
        // Enhanced Feature 2: Double-click detection
        let doubleClickDetected = detectDoubleClick(at: mouseUpLocation, time: currentTime)
        
        if doubleClickDetected {
            debugPrint("Double-click detected at \(mouseUpLocation) - triggering text selection")
            
            // Segfault fix: Check if popup is already being created OR already visible
            if isCreatingPopup {
                os_log("Popup creation in progress, skipping double-click", log: .popup, type: .info)
                return
            }
            
            // CRITICAL: If popup is already visible, ignore double-click completely to prevent segfault
            if let existingPopup = popupWindow, existingPopup.isVisible {
                debugPrint("🔧 DEBUG: Popup already visible, ignoring double-click to prevent segfault")
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                debugPrint("Preparing to get selected text from double-click...")
                self?.getSelectedTextForDoubleClick()
            }
            return
        }
        
        // Original drag detection logic
        guard let mouseDownLoc = mouseDownLocation else {
            print("No mouse down location recorded")
            return
        }
        
        let distance = sqrt(pow(mouseUpLocation.x - mouseDownLoc.x, 2) + pow(mouseUpLocation.y - mouseDownLoc.y, 2))
        let timeDiff = currentTime - mouseDownTime
        
        debugPrint("Mouse up at location: \(mouseUpLocation), distance: \(distance), time: \(timeDiff)")
        
        // Enhanced Feature 3: Improved false positive prevention
        if isLikelyUIInteraction(mouseDown: mouseDownLoc, mouseUp: mouseUpLocation, distance: distance) {
            print("Detected UI interaction - not triggering text selection")
            resetTrackingVariables()
            return
        }
        
        // Module 4: Enhanced event validation with multiple criteria
        let originalCriteriaMet = distance > 5 || timeDiff > 0.3
        
        if originalCriteriaMet {
            print("Original criteria met: distance=\(distance), time=\(timeDiff)")
            
            // Additional validation using EnhancedEventValidator
            let enhancedValidation = EnhancedEventValidator.validateSelectionGesture(
                mouseDown: mouseDownLoc,
                mouseUp: mouseUpLocation,
                duration: timeDiff,
                distance: distance
            )
            
            if enhancedValidation.isValid {
                debugPrint("Enhanced validation passed: \(enhancedValidation.reason)")
                print("Detected potential text selection (drag or long press)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    debugPrint("Preparing to get selected text...")
                    guard let self = self else {
                        print("AppDelegate has been released")
                        return
                    }
                    self.getSelectedText(mouseUpLocation: mouseUpLocation, currentTime: currentTime)
                }
            } else {
                debugPrint("Enhanced validation failed: \(enhancedValidation.reason)")
            }
        } else {
            print("Simple click detected, not checking for text selection")
        }
        
        resetTrackingVariables()
    }
    
    // Enhanced Feature 2: Double-click detection
    private func detectDoubleClick(at location: CGPoint, time: CFTimeInterval) -> Bool {
        let doubleClickTimeThreshold: CFTimeInterval = 0.5 // 500ms
        let doubleClickDistanceThreshold: CGFloat = 10 // 10px
        
        let timeDiff = time - lastClickTime
        let distance = sqrt(pow(location.x - lastClickLocation.x, 2) + pow(location.y - lastClickLocation.y, 2))
        
        let isDoubleClick = timeDiff < doubleClickTimeThreshold && distance < doubleClickDistanceThreshold
        
        // CRITICAL: If popup is visible at same location, ignore double-click to prevent segfault
        if let existingPopup = popupWindow, existingPopup.isVisible {
            let popupCenter = NSPoint(x: existingPopup.frame.midX, y: existingPopup.frame.midY)
            let distanceFromPopup = sqrt(pow(location.x - popupCenter.x, 2) + pow(location.y - popupCenter.y, 2))
            
            if distanceFromPopup < 100 { // If clicking near existing popup
                debugPrint("🔧 DEBUG: Double-click near existing popup (\(distanceFromPopup)px), ignoring to prevent segfault")
                lastClickTime = time // Update to prevent future detection issues
                lastClickLocation = location
                clickCount = 0 // Reset
                return false
            }
        }
        
        // Update click tracking
        lastClickTime = time
        lastClickLocation = location
        
        if isDoubleClick {
            clickCount += 1
            if clickCount >= 2 {
                clickCount = 0 // Reset for next potential double-click
                return true
            }
        } else {
            clickCount = 1 // Reset count for new click sequence
        }
        
        return false
    }
    
    // Enhanced Feature 3: Improved false positive prevention
    private func isLikelyUIInteraction(mouseDown: CGPoint, mouseUp: CGPoint, distance: Double) -> Bool {
        // Check for common UI interaction patterns
        
        // 1. Very small movements (likely button clicks)
        if distance < 2 {
            return true
        }
        
        // 2. Perfectly vertical or horizontal movements (likely scrollbar/slider interactions)
        let deltaX = abs(mouseUp.x - mouseDown.x)
        let deltaY = abs(mouseUp.y - mouseDown.y)
        
        if deltaX < 5 && deltaY > 20 {
            print("Vertical UI interaction detected")
            return true
        }
        
        if deltaY < 5 && deltaX > 20 {
            print("Horizontal UI interaction detected")
            return true
        }
        
        // 3. Check if movement is in typical UI control areas (top/bottom edges)
        guard let screen = NSScreen.main else { return false }
        let screenFrame = screen.visibleFrame
        
        // Top area (menu bars, title bars)
        if mouseDown.y > screenFrame.maxY - 100 {
            print("Top area UI interaction detected")
            return true
        }
        
        // Bottom area (dock, taskbar)
        if mouseDown.y < screenFrame.minY + 100 {
            print("Bottom area UI interaction detected")
            return true
        }
        
        return false
    }
    
    private func resetTrackingVariables() {
        mouseDownLocation = nil
        mouseDownTime = 0
    }
    
    // Segfault fix: Public method to reset creation flag
    func resetPopupCreationFlag() {
        isCreatingPopup = false
    }
    
    func getSelectedText(mouseUpLocation: CGPoint? = nil, currentTime: CFTimeInterval = 0) {
        if let text = getSelectedTextViaAccessibility(mouseUpLocation: mouseUpLocation, currentTime: currentTime), !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
            
            // Module 1: Enhanced validation with text frame checking
            // First get the focused element for frame validation
            let systemWideElement = AXUIElementCreateSystemWide()
            var focusedElement: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            
            if result == .success, let element = focusedElement {
                let axElement = element as! AXUIElement
                let currentMouseLocation = NSEvent.mouseLocation
                
                // Use TextFrameValidator to enhance validation (preserves original behavior as fallback)
                let isValidPosition = TextFrameValidator.validateMousePositionInTextFrame(
                    axElement,
                    mouseDownLocation: mouseDownLocation,
                    currentMouseLocation: currentMouseLocation
                )
                
                if isValidPosition {
                    debugPrint("TextFrameValidator: Position validation passed, showing popup")
                    self.showPopupMenu(for: text)
                } else {
                    debugPrint("TextFrameValidator: Position validation failed, suppressing popup")
                }
            } else {
                // Fallback to original behavior if we can't get the focused element
                print("TextFrameValidator: Could not get focused element, using original behavior")
                self.showPopupMenu(for: text)
            }
        }
    }
    
    // Enhanced method for double-click: more lenient validation
    func getSelectedTextForDoubleClick() {
        // Additional safety check
        if isCreatingPopup {
            print("Popup creation already in progress, skipping double-click text selection")
            return
        }
        
        if let text = getSelectedTextViaAccessibility(), !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
            debugPrint("Double-click text selection successful: \(text.prefix(50))...")
            self.showPopupMenu(for: text)
        } else {
            debugPrint("Double-click detected but no text selected")
        }
    }
    
    func getSelectedTextViaAccessibility(mouseUpLocation: CGPoint? = nil, currentTime: CFTimeInterval = 0) -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // Get application info
        let runningApp = NSWorkspace.shared.frontmostApplication
        let runningAppName = runningApp?.localizedName ?? "Unknown"
        
        var appElement: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXTopLevelUIElementAttribute as CFString, &appElement)
        
        var appName: CFTypeRef?
        if let app = appElement {
            AXUIElementCopyAttributeValue(app as! AXUIElement, kAXTitleAttribute as CFString, &appName)
        }
        
        let applicationName = (appName as? String) ?? runningAppName
        
        // Module 3: Enhanced application-specific handling
        // Try ApplicationSpecificHandler first (includes enhanced Sublime Text support)
        let gestureDataForHandler: FallbackMethodController.GestureData?
        if let mouseDown = mouseDownLocation, let mouseUp = mouseUpLocation {
            let distance = sqrt(pow(mouseUp.x - mouseDown.x, 2) + pow(mouseUp.y - mouseDown.y, 2))
            let timeDiff = currentTime - mouseDownTime
            
            gestureDataForHandler = FallbackMethodController.GestureData(
                mouseDown: mouseDown,
                mouseUp: mouseUp,
                duration: timeDiff,
                distance: distance
            )
        } else {
            gestureDataForHandler = nil
        }
        
        if let text = ApplicationSpecificHandler.getTextForApplication(applicationName, element: axElement, gestureData: gestureDataForHandler) {
            print("Got text via ApplicationSpecificHandler: \(text)")
            return text
        }
        
        // Preserve original Sublime Text handling as additional fallback
        if applicationName.contains("Sublime Text") || runningAppName.contains("Sublime Text") {
            print("Using original Sublime Text fallback")
            // Still use FallbackMethodController for consistency, but Sublime Text should generally pass
            let gestureData: FallbackMethodController.GestureData?
            if let mouseDown = mouseDownLocation, let mouseUp = mouseUpLocation {
                let distance = sqrt(pow(mouseUp.x - mouseDown.x, 2) + pow(mouseUp.y - mouseDown.y, 2))
                let timeDiff = currentTime - mouseDownTime
                
                gestureData = FallbackMethodController.GestureData(
                    mouseDown: mouseDown,
                    mouseUp: mouseUp,
                    duration: timeDiff,
                    distance: distance
                )
            } else {
                gestureData = nil
            }
            
            if FallbackMethodController.shouldUseCmdCFallback(for: "sublime text", gestureData: gestureData) {
                return tryGetTextViaCopy()
            }
            return nil
        }
        
        // Try standard accessibility methods for other applications (preserved)
        if let text = tryGetSelectedText(from: axElement) {
            return text
        }
        
        // Module 6: Use FallbackMethodController to determine if CMD+C should be used
        let gestureData: FallbackMethodController.GestureData?
        if let mouseDown = mouseDownLocation, let mouseUp = mouseUpLocation {
            let distance = sqrt(pow(mouseUp.x - mouseDown.x, 2) + pow(mouseUp.y - mouseDown.y, 2))
            let timeDiff = currentTime - mouseDownTime
            
            gestureData = FallbackMethodController.GestureData(
                mouseDown: mouseDown,
                mouseUp: mouseUp,
                duration: timeDiff,
                distance: distance
            )
        } else {
            gestureData = nil
        }
        
        // Check if CMD+C fallback should be used for this application
        if FallbackMethodController.shouldUseCmdCFallback(for: applicationName, gestureData: gestureData) {
            print("FallbackMethodController approved CMD+C for \(applicationName)")
            return tryGetTextViaCopy()
        } else {
            print("FallbackMethodController rejected CMD+C for \(applicationName)")
            return nil
        }
    }
    
    
    
    func tryGetTextViaCopy() -> String? {
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
        
        // Wait a bit for the copy to complete
        usleep(100000) // 0.1 seconds
        
        // Check if clipboard has new content
        let newContent = pasteboard.string(forType: .string)
        
        // Always restore original clipboard content immediately
        if let original = originalContent {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        } else {
            pasteboard.clearContents()
        }
        
        // Return the captured content if valid
        if let content = newContent, !content.isEmpty, content != originalContent {
            return content
        }
        
        return nil
    }
    
    func analyzeElement(_ element: AXUIElement, depth: Int) {
        // Limit recursion depth to avoid crashes
        guard depth < 3 else { return }
        
        let indent = String(repeating: "  ", count: depth)
        
        // Get element role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? "Unknown"
        
        // Get element description
        var roleDescription: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescription)
        let roleDesc = roleDescription as? String ?? ""
        
        print("\(indent)Element: \(roleString) (\(roleDesc))")
        
        // Show key attributes only
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
            if let names = attributeNames as? [String] {
                // Show values for selection-related attributes only
                let selectionAttributes = ["AXSelectedText", "AXSelectedTextRange"]
                
                for name in names where selectionAttributes.contains(name) {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success {
                        if name == "AXSelectedText", let text = value as? String, !text.isEmpty {
                            print("\(indent)  \(name): \(text)")
                        } else if name == "AXSelectedTextRange" {
                            if let range = value, CFGetTypeID(range) == AXValueGetTypeID() {
                                let axValue = range as! AXValue
                                var cfRange = CFRange()
                                if AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0 {
                                    print("\(indent)  \(name): location=\(cfRange.location), length=\(cfRange.length)")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Recursively analyze children
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childArray = children as? [AXUIElement] {
                for child in childArray {
                    analyzeElement(child, depth: depth + 1)
                }
            }
        }
    }
    
    func tryGetSelectedText(from element: AXUIElement) -> String? {
        // Method 1: Direct get selected text
        var selectedText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success {
            if let text = selectedText as? String, !text.isEmpty {
                print("Found selected text: \(text)")
                return text
            }
        }
        
        // Method 2: Get text via selected range
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            print("Found selected range: \(String(describing: selectedRange))")
            
            // Try to get text using range
            if let range = selectedRange, CFGetTypeID(range) == AXValueGetTypeID() {
                let axValue = range as! AXValue
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                    print("Range: location=\(cfRange.location), length=\(cfRange.length)")
                    
                    if cfRange.length > 0 {
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
                                        print("Got text via range: \(selectedText)")
                                        return selectedText
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Method 3: Check child elements
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childArray = children as? [AXUIElement] {
                print("Checking \(childArray.count) child elements...")
                for (index, child) in childArray.enumerated() {
                    print("Checking child element \(index)...")
                    if let text = tryGetSelectedText(from: child) {
                        print("Got text from child element \(index): \(text)")
                        return text
                    }
                }
                print("No selected text in any child elements")
            }
        }
        
        print("tryGetSelectedText returning nil")
        return nil
    }
    
    
    func showPopupMenu(for text: String) {
        debugPrint("🔧 DEBUG: showPopupMenu called with text: \(text.prefix(20))...")
        
        // Segfault fix: Prevent concurrent popup creation
        popupCreationQueue.async { [weak self] in
            debugPrint("🔧 DEBUG: In popupCreationQueue")
            guard let self = self else { 
                debugPrint("🔧 DEBUG: self is nil in popupCreationQueue")
                return 
            }
            
            // Check if already creating a popup
            if self.isCreatingPopup {
                debugPrint("🔧 DEBUG: Popup creation already in progress, skipping...")
                return
            }
            
            debugPrint("🔧 DEBUG: Setting isCreatingPopup = true")
            self.isCreatingPopup = true
            
            DispatchQueue.main.async { [weak self] in
                debugPrint("🔧 DEBUG: In main async block")
                guard let self = self else { 
                    debugPrint("🔧 DEBUG: self is nil in main async")
                    return 
                }
                
                debugPrint("🔧 DEBUG: About to close old window")
                // 先確保舊窗口完全關閉
                if let oldWindow = self.popupWindow {
                    debugPrint("🔧 DEBUG: Closing old window")
                    // Segfault fix: Safer window cleanup
                    self.popupWindow = nil // Clear reference BEFORE closing
                    DispatchQueue.main.async {
                        oldWindow.close()
                    }
                }
                
                // 短暫延遲確保清理完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    debugPrint("🔧 DEBUG: In delayed creation block")
                    guard let self = self else { 
                        debugPrint("🔧 DEBUG: self is nil in delayed block")
                        return 
                    }
                
                debugPrint("🔧 DEBUG: Creating new popup window")
                let mouseLocation = NSEvent.mouseLocation
                let menuWindow = PopupMenuWindow(selectedText: text)
                debugPrint("🔧 DEBUG: PopupMenuWindow created successfully")
                
                // Module 2: Enhanced smart positioning with fallback to original logic
                let windowSize = NSSize(width: 180, height: 40)
                
                // Original positioning logic (preserved as baseline)
                var originalOrigin = NSPoint(x: mouseLocation.x - 90, y: mouseLocation.y - 60)
                
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let windowWidth: CGFloat = 180
                    
                    // Apply original horizontal positioning
                    if originalOrigin.x + windowWidth > screenFrame.maxX {
                        originalOrigin.x = screenFrame.maxX - windowWidth
                    }
                    if originalOrigin.x < screenFrame.minX {
                        originalOrigin.x = screenFrame.minX
                    }
                    
                    // Apply original vertical positioning - below by default, above if no space
                    if originalOrigin.y < screenFrame.minY {
                        originalOrigin.y = mouseLocation.y + 20
                    }
                }
                
                // Calculate smart position using PopupPositionCalculator
                let smartOrigin = PopupPositionCalculator.calculateSmartPosition(
                    originalPosition: originalOrigin,
                    mouseLocation: mouseLocation,
                    mouseDownLocation: self.mouseDownLocation,
                    windowSize: windowSize,
                    selectedText: text
                )
                
                // Use smart positioning as primary, original as fallback
                let finalOrigin = smartOrigin
                
                menuWindow.setFrameOrigin(finalOrigin)
                
                // Add fade in + scale animation according to spec
                menuWindow.alphaValue = 0.0
                menuWindow.setFrame(menuWindow.frame.insetBy(dx: 5, dy: 2.5), display: false)
                menuWindow.makeKeyAndOrderFront(nil)
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    menuWindow.animator().alphaValue = 1.0
                    menuWindow.animator().setFrame(menuWindow.frame.insetBy(dx: -5, dy: -2.5), display: true)
                }
                
                self.popupWindow = menuWindow
                
                // Reset the creation flag
                self.isCreatingPopup = false
                }
            }
        }
    }
    
    func hidePopupMenu() {
        DispatchQueue.main.async {
            if let window = self.popupWindow {
                // Segfault fix: Safer window cleanup
                self.popupWindow = nil // Clear reference BEFORE closing
                DispatchQueue.main.async {
                    window.close()
                }
            }
            // Segfault fix: Reset creation flag
            self.isCreatingPopup = false
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
}

class HoverButton: NSButton {
    private let defaultColors = [
        NSColor(red: 0.898, green: 0.294, blue: 0.294, alpha: 1.0), // #E54B4B 紅色
        NSColor(red: 0.961, green: 0.608, blue: 0.196, alpha: 1.0), // #F59B32 橘色
        NSColor(red: 0.969, green: 0.851, blue: 0.322, alpha: 1.0), // #F7D952 黃色
        NSColor(red: 0.541, green: 0.835, blue: 0.322, alpha: 1.0), // #8AD552 綠色
        NSColor(red: 0.627, green: 0.451, blue: 0.831, alpha: 1.0), // #A073D4 紫色
        NSColor(red: 0.620, green: 0.620, blue: 0.620, alpha: 1.0)  // #9E9E9E 灰色
    ]
    private var highlightColor: NSColor
    
    override init(frame frameRect: NSRect) {
        // Randomly select a highlight color
        self.highlightColor = defaultColors.randomElement() ?? defaultColors[0]
        super.init(frame: frameRect)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        self.highlightColor = defaultColors.randomElement() ?? defaultColors[0]
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        
        // Animate background color and text color change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Set highlight background
            self.layer?.backgroundColor = self.highlightColor.cgColor
            
            // Change text color to white as per spec
            self.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        // Animate back to default state
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Remove background
            self.layer?.backgroundColor = NSColor.clear.cgColor
            
            // Restore original text color based on appearance
            if #available(macOS 10.14, *) {
                let effectiveAppearance = NSApp.effectiveAppearance
                if effectiveAppearance.name == .darkAqua {
                    self.contentTintColor = NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1.0) // #E0E0E0
                } else {
                    self.contentTintColor = NSColor(red: 0.173, green: 0.173, blue: 0.173, alpha: 1.0) // #2C2C2C
                }
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Add pressed state effect - slightly darker background
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05
            
            // Make background slightly darker
            let darkerColor = highlightColor.blended(withFraction: 0.2, of: NSColor.black) ?? highlightColor
            self.layer?.backgroundColor = darkerColor.cgColor
        }
        
        super.mouseDown(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        // Return to hover state
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05
            
            // Return to normal highlight color
            self.layer?.backgroundColor = self.highlightColor.cgColor
        }
        
        super.mouseUp(with: event)
    }
}

class PopupMenuWindow: NSWindow {
    let selectedText: String
    var timeoutTimer: Timer?
    private var buttons: [NSButton] = []
    
    // Module 5: Enhanced dismissal management
    private var dismissalManager: PopupDismissalManager?
    
    init(selectedText: String) {
        debugPrint("🔧 DEBUG: PopupMenuWindow.init called")
        self.selectedText = selectedText
        
        // Calculate dynamic width based on buttons (2 buttons + 1 separator + padding)
        // Each button ~80px, 1 separator 1px, padding 20px total  
        let contentRect = NSRect(x: 0, y: 0, width: 180, height: 40)
        debugPrint("🔧 DEBUG: About to call super.init")
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        debugPrint("🔧 DEBUG: super.init completed")
        
        debugPrint("🔧 DEBUG: Setting up window")
        setupWindow()
        debugPrint("🔧 DEBUG: Setting up buttons")
        setupButtons()
        debugPrint("🔧 DEBUG: Setting up timeout")
        setupTimeout()
        
        debugPrint("🔧 DEBUG: Setting up enhanced dismissal")
        // Module 5: Setup enhanced dismissal management (preserves original timer)
        // Delay dismissal manager setup to avoid initialization conflicts
        DispatchQueue.main.async { [weak self] in
            self?.setupEnhancedDismissal()
        }
        debugPrint("🔧 DEBUG: PopupMenuWindow.init completed")
    }
    
    func setupTimeout() {
        // Preserve original 1.5 second timeout behavior
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeAndNotify()
            }
        }
    }
    
    // Module 5: Enhanced dismissal setup
    func setupEnhancedDismissal() {
        dismissalManager = PopupDismissalManager(popupWindow: self)
    }
    
    override func close() {
        print("close() called")
        
        // CRITICAL: Clean up dismissal manager FIRST to remove event monitors
        dismissalManager?.cleanup()
        dismissalManager = nil
        
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        super.close()
    }
    
    deinit {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Module 5: Ensure cleanup on deallocation
        dismissalManager?.cleanup()
        dismissalManager = nil
    }
    
    func setupWindow() {
        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        hasShadow = true
        
        guard let currentContentView = contentView else { return }
        
        let visualEffect = NSVisualEffectView(frame: currentContentView.bounds)
        
        // Configure for pill shape with proper blur and transparency
        if #available(macOS 10.14, *) {
            visualEffect.material = .popover
        } else {
            visualEffect.material = .hudWindow
        }
        
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        
        // Pill shape: corner radius = height / 2 = 20px
        visualEffect.layer?.cornerRadius = 20
        visualEffect.autoresizingMask = [.width, .height]
        
        // Add proper shadow according to spec
        if let layer = visualEffect.layer {
            layer.shadowOpacity = 1.0
            layer.shadowOffset = NSSize(width: 0, height: -3)
            layer.shadowRadius = 6
            
            // Shadow color adapts to appearance
            if #available(macOS 10.14, *) {
                layer.shadowColor = NSColor.shadowColor.cgColor
            } else {
                layer.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
            }
        }
        
        contentView = visualEffect
    }
    
    func setupButtons() {
        guard let contentView = contentView else { return }
        
        // Button specifications according to UI spec
        let buttonHeight: CGFloat = 40
        let buttonWidth: CGFloat = 80
        let separatorWidth: CGFloat = 1
        let leftPadding: CGFloat = 10
        
        // Create buttons with proper styling
        let copyButton = createButton(title: "Copy", action: #selector(copyAction))  
        let searchButton = createButton(title: "🔍", action: #selector(searchAction))
        
        buttons = [copyButton, searchButton]
        
        // Position buttons horizontally with separators
        var currentX: CGFloat = leftPadding
        
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: currentX, y: 0, width: buttonWidth, height: buttonHeight)
            contentView.addSubview(button)
            currentX += buttonWidth
            
            // Add separator after each button except the last one
            if index < buttons.count - 1 {
                let separator = createSeparator()
                separator.frame = NSRect(x: currentX, y: 10, width: separatorWidth, height: 20)
                contentView.addSubview(separator)
                currentX += separatorWidth
            }
        }
    }
    
    private func createButton(title: String, action: Selector) -> NSButton {
        let button = HoverButton()
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.wantsLayer = true
        
        // Font styling according to spec
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        
        // Set initial text color according to spec
        if #available(macOS 10.14, *) {
            let effectiveAppearance = NSApp.effectiveAppearance
            if effectiveAppearance.name == .darkAqua {
                button.contentTintColor = NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1.0) // #E0E0E0
            } else {
                button.contentTintColor = NSColor(red: 0.173, green: 0.173, blue: 0.173, alpha: 1.0) // #2C2C2C
            }
        }
        
        // Setup corner radius
        button.layer?.cornerRadius = 8
        
        return button
    }
    
    private func createSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        
        // Separator color that adapts to system appearance  
        if #available(macOS 10.14, *) {
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        } else {
            separator.layer?.backgroundColor = NSColor.lightGray.cgColor
        }
        
        return separator
    }
    
    
    @objc func copyAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
        closeAndNotify()
    }
    
    
    @objc func searchAction() {
        // Open default browser with Google search
        let query = selectedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURL = "https://www.google.com/search?q=\(query)"
        
        if let url = URL(string: searchURL) {
            NSWorkspace.shared.open(url)
        }
        
        closeAndNotify()
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        closeAndNotify()
    }
    
    override func resignKey() {
        super.resignKey()
        closeAndNotify()
    }
    
    func closeAndNotify() {
        // Clean up timer first
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Notify AppDelegate to clear reference
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if appDelegate.popupWindow === self {
                appDelegate.popupWindow = nil
                // Segfault fix: Reset creation flag when window closes
                appDelegate.resetPopupCreationFlag()
            }
        }
        
        // Add fade out animation according to spec (100ms)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            // Use orderOut instead of performClose to avoid potential beep sounds
            debugPrint("🔧 DEBUG: Window closed gracefully without performClose")
        })
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()