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
        setupEnhancedMonitoring()
    }
    
    func setupEnhancedMonitoring() {
        // Initialize multi-layered monitoring system
        EnhancedEventValidator.setupWindowMonitoring()
        // WindowOperationDetector is already a singleton and auto-initializes
        
        // Initialize Easydict-style event monitor
        EasydictEventMonitor.setup(with: self)
        
        os_log("Enhanced monitoring system initialized with Easydict detection", log: .lifecycle, type: .info)
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
        // Include drag events for Easydict-style sequence detection
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | 
                       (1 << CGEventType.leftMouseUp.rawValue) |
                       (1 << CGEventType.leftMouseDragged.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                
                // Route events to both old and new detection systems
                if type == .leftMouseDown {
                    appDelegate.handleMouseDown(event: event)
                    EasydictEventMonitor.handleLeftMouseDown(at: event.location)
                } else if type == .leftMouseDragged {
                    // New: Handle drag events for sequence analysis
                    let nsEvent = NSEvent(cgEvent: event)!
                    EasydictEventMonitor.handleLeftMouseDragged(at: event.location, event: nsEvent)
                } else if type == .leftMouseUp {
                    appDelegate.handleMouseUp(event: event)
                    EasydictEventMonitor.handleLeftMouseUp(at: event.location)
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
        
        // Check if Easydict detection should override traditional detection
        if EasydictEventMonitor.shouldUseEasydictDetection() {
            os_log("Using Easydict detection - skipping traditional validation", log: .textSelection, type: .info)
            // Easydict monitor handles everything via delayed validation
            resetTrackingVariables()
            return
        }
        
        // Enhanced Feature 2: Double-click detection (preserved for compatibility)
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
        
        // Traditional detection (fallback when Easydict detection is not active)
        guard let mouseDownLoc = mouseDownLocation else {
            print("No mouse down location recorded")
            return
        }
        
        let distance = sqrt(pow(mouseUpLocation.x - mouseDownLoc.x, 2) + pow(mouseUpLocation.y - mouseDownLoc.y, 2))
        let timeDiff = currentTime - mouseDownTime
        
        debugPrint("Traditional detection - Mouse up at location: \(mouseUpLocation), distance: \(distance), time: \(timeDiff)")
        
        // Simplified criteria to be less strict (closer to Easydict)
        let shouldTrigger = distance > 1 || timeDiff > 0.1  // Much more lenient
        
        if shouldTrigger {
            os_log("Lenient criteria met: distance=%.1f, time=%.3f", log: .validation, type: .info, distance, timeDiff)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + EasydictEventMonitor.kDelayGetSelectedTextTime) { [weak self] in
                debugPrint("Delayed text extraction via traditional method...")
                guard let self = self else {
                    print("AppDelegate has been released")
                    return
                }
                self.getSelectedText(mouseUpLocation: mouseUpLocation, currentTime: currentTime)
            }
        } else {
            os_log("Traditional criteria not met - ignoring", log: .validation, type: .debug)
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
        
        // Enhanced Easydict-style fallback system
        let gestureData: GestureData?
        if let mouseDown = mouseDownLocation, let mouseUp = mouseUpLocation {
            let distance = sqrt(pow(mouseUp.x - mouseDown.x, 2) + pow(mouseUp.y - mouseDown.y, 2))
            let timeDiff = currentTime - mouseDownTime
            
            gestureData = GestureData(
                mouseDown: mouseDown,
                mouseUp: mouseUp,
                duration: timeDiff,
                distance: distance
            )
        } else {
            gestureData = nil
        }
        
        // Use EasydictFallbackController for smart fallback decisions
        if EasydictFallbackController.shouldUseFallback(for: applicationName, gestureData: gestureData) {
            os_log("Using EasydictFallbackController for %{public}@", log: .textSelection, type: .info, applicationName)
            return EasydictFallbackController.getSelectedTextWithPreferences(
                for: applicationName, 
                element: axElement, 
                gestureData: gestureData
            )
        } else {
            os_log("EasydictFallbackController rejected fallback for %{public}@", log: .textSelection, type: .info, applicationName)
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
        // Cleanup multi-layered monitoring system
        EnhancedEventValidator.cleanup()
        WindowOperationDetector.shared.cleanup()
        EasydictEventMonitor.cleanup()
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        
        os_log("Application cleanup completed", log: .lifecycle, type: .info)
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
        
        // Ensure window has no border or frame
        if let windowFrame = contentView?.superview {
            windowFrame.wantsLayer = true
            if let layer = windowFrame.layer {
                layer.borderWidth = 0
                layer.backgroundColor = NSColor.clear.cgColor
            }
        }
        
        guard let currentContentView = contentView else { return }
        
        // Create a simple colored view instead of NSVisualEffectView to avoid border issues
        let backgroundView = NSView(frame: currentContentView.bounds)
        backgroundView.wantsLayer = true
        backgroundView.autoresizingMask = [.width, .height]
        
        if let layer = backgroundView.layer {
            // Pill shape: corner radius = height / 2 = 20px
            layer.cornerRadius = 20
            
            // Clean background with appropriate opacity for modern macOS look
            if #available(macOS 10.14, *) {
                // Use dynamic system colors that adapt to light/dark mode
                layer.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
            } else {
                layer.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
            }
            
            // Ensure no border
            layer.borderWidth = 0
            layer.borderColor = NSColor.clear.cgColor
            
            // Add proper shadow according to spec
            layer.shadowOpacity = 0.3
            layer.shadowOffset = NSSize(width: 0, height: -3)
            layer.shadowRadius = 6
            layer.shadowColor = NSColor.black.cgColor
        }
        
        contentView = backgroundView
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