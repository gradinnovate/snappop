import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popupWindow: NSWindow?
    var eventTap: CFMachPort?
    var mouseDownLocation: CGPoint?
    var mouseDownTime: CFTimeInterval = 0
    
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
        print("Mouse down at location: \(mouseDownLocation!)")
    }
    
    func handleMouseUp(event: CGEvent) {
        guard let mouseDownLoc = mouseDownLocation else {
            print("No mouse down location recorded")
            return
        }
        
        let mouseUpLocation = event.location
        let distance = sqrt(pow(mouseUpLocation.x - mouseDownLoc.x, 2) + pow(mouseUpLocation.y - mouseDownLoc.y, 2))
        let timeDiff = CFAbsoluteTimeGetCurrent() - mouseDownTime
        
        print("Mouse up at location: \(mouseUpLocation), distance: \(distance), time: \(timeDiff)")
        
        // Only trigger text selection if there was movement (drag) or held for a while
        // This prevents simple clicks from triggering
        if distance > 5 || timeDiff > 0.3 {
            print("Detected potential text selection (drag or long press)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                print("Preparing to get selected text...")
                guard let self = self else {
                    print("AppDelegate has been released")
                    return
                }
                self.getSelectedText()
            }
        } else {
            print("Simple click detected, not checking for text selection")
        }
        
        // Reset tracking variables
        mouseDownLocation = nil
        mouseDownTime = 0
    }
    
    func getSelectedText() {
        if let text = getSelectedTextViaAccessibility(), !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
            print("Got selected text: \(text)")
            self.showPopupMenu(for: text)
        } else {
            print("Failed to get selected text")
        }
    }
    
    func getSelectedTextViaAccessibility() -> String? {
        print("Trying Accessibility API...")
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            print("Cannot get focused element")
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // Get application info - try multiple methods
        var appElement: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXTopLevelUIElementAttribute as CFString, &appElement)
        
        var appName: CFTypeRef?
        if let app = appElement {
            AXUIElementCopyAttributeValue(app as! AXUIElement, kAXTitleAttribute as CFString, &appName)
        }
        
        // Also try getting the running application name
        let runningApp = NSWorkspace.shared.frontmostApplication
        let runningAppName = runningApp?.localizedName ?? "Unknown"
        
        let applicationName = (appName as? String) ?? runningAppName
        print("Current application: \(applicationName) (frontmost: \(runningAppName))")
        
        // Analyze element details
        analyzeElement(axElement, depth: 0)
        
        // Try application-specific methods first
        if applicationName.contains("Sublime Text") || runningAppName.contains("Sublime Text") {
            print("Detected Sublime Text, using specialized methods...")
            print("=== SEARCHING FOR TEXT EDITOR ELEMENTS ===")
            // First, let's find the actual text editor elements
            findTextEditorElements(from: axElement, depth: 0)
            print("=== END TEXT EDITOR SEARCH ===")
            
            if let text = tryGetSublimeTextSelection(from: axElement) {
                return text
            }
        }
        
        // Try multiple generic methods to get selected text
        if let text = tryGetSelectedText(from: axElement) {
            return text
        }
        
        // Try traversing child elements for Sublime Text and other editors
        if let text = tryGetSelectedTextFromChildren(element: axElement) {
            return text
        }
        
        print("All methods failed to get selected text")
        return nil
    }
    
    func tryGetSublimeTextSelection(from element: AXUIElement) -> String? {
        print("Trying Sublime Text specific methods...")
        
        // Method 1: Look for AXStaticText elements that contain full text content
        // Based on the structure analysis, Sublime Text exposes text via AXStaticText elements
        if let text = findSublimeTextContent(from: element) {
            print("Found text content in Sublime Text, attempting CMD+C to get selection...")
            // We found text content, now use CMD+C to get the actual selection
            if let selectedText = tryGetTextViaCopy() {
                return selectedText
            }
        }
        
        // Method 2: Exhaustive search through all descendants for text selection
        if let text = deepSearchForSelection(element: element, maxDepth: 5) {
            return text
        }
        
        // Method 3: Try all alternative accessibility attributes
        if let text = tryAlternativeAccessibilityMethods(element: element) {
            return text
        }
        
        // Method 4: Direct CMD+C as fallback
        if let text = tryGetTextViaCopy() {
            return text
        }
        
        return nil
    }
    
    func findSublimeTextContent(from element: AXUIElement) -> String? {
        // Look for AXStaticText elements with actual content
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childElements = children as? [AXUIElement] {
                for child in childElements {
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
                    
                    if let roleStr = role as? String, roleStr == "AXStaticText" {
                        // Check if this element has substantial text content
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value) == .success {
                            if let text = value as? String, text.count > 10 {
                                print("Found AXStaticText with content length: \(text.count)")
                                return text
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    func findTextEditorElements(from element: AXUIElement, depth: Int) {
        guard depth < 10 else { return }
        
        let indent = String(repeating: "    ", count: depth)
        
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? "Unknown"
        
        print("\(indent)Examining element: \(roleString) at depth \(depth)")
        
        // Look for elements that might be text editors
        let editorRoles = ["AXTextArea", "AXScrollArea", "AXDocument", "AXWebArea", "AXTextDocument"]
        
        if editorRoles.contains(roleString) {
            print("\(indent)📝 FOUND POTENTIAL TEXT EDITOR: \(roleString)")
            
            // Analyze this element in detail
            var attributeNames: CFArray?
            if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
                if let names = attributeNames as? [String] {
                    print("\(indent)    Attributes: \(names)")
                    
                    // Check for selection-related attributes
                    for attr in ["AXSelectedText", "AXSelectedTextRange", "AXValue", "AXDocument"] {
                        if names.contains(attr) {
                            var value: CFTypeRef?
                            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success {
                                if attr == "AXSelectedTextRange", let range = value {
                                    if CFGetTypeID(range) == AXValueGetTypeID() {
                                        let axValue = range as! AXValue
                                        var cfRange = CFRange()
                                        if AXValueGetValue(axValue, .cfRange, &cfRange) {
                                            print("\(indent)    \(attr): location=\(cfRange.location), length=\(cfRange.length)")
                                        }
                                    }
                                } else if let text = value as? String {
                                    let preview = text.prefix(50)
                                    print("\(indent)    \(attr): \(preview)...")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Analyze ALL AXStaticText elements in detail
        if roleString == "AXStaticText" {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
                if let text = value as? String {
                    print("\(indent)📝 ANALYZING AXStaticText: \(text.prefix(30))... (length: \(text.count))")
                    
                    // Deep analysis of ALL text elements
                    print("\(indent)   🔍 DEEP ANALYSIS OF TEXT ELEMENT:")
                    var attributeNames: CFArray?
                    if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
                        if let names = attributeNames as? [String] {
                            print("\(indent)       All attributes: \(names)")
                            
                            // Check ALL attributes that might contain selection info
                            let selectionAttrs = ["AXSelectedText", "AXSelectedTextRange", "AXVisibleCharacterRange", "AXInsertionPointLineNumber", "AXNumberOfCharacters"]
                            
                            for attr in selectionAttrs {
                                if names.contains(attr) {
                                    var value: CFTypeRef?
                                    if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success {
                                        if attr == "AXSelectedTextRange" || attr == "AXVisibleCharacterRange" {
                                            if let range = value, CFGetTypeID(range) == AXValueGetTypeID() {
                                                let axValue = range as! AXValue
                                                var cfRange = CFRange()
                                                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                                                    print("\(indent)       \(attr): location=\(cfRange.location), length=\(cfRange.length)")
                                                }
                                            }
                                        } else if let stringValue = value as? String {
                                            print("\(indent)       \(attr): \(stringValue)")
                                        } else if let numberValue = value as? NSNumber {
                                            print("\(indent)       \(attr): \(numberValue)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    print("\(indent)📝 AXStaticText with no text value")
                }
            } else {
                print("\(indent)📝 AXStaticText (cannot read value)")
            }
        }
        
        // Check Groups as well
        if roleString == "AXGroup" {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
                if let text = value as? String, text.count > 10 {
                    print("\(indent)📄 Group with text content: \(text.prefix(30))... (length: \(text.count))")
                }
            }
        }
        
        // Recursively search children
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childArray = children as? [AXUIElement] {
                if childArray.count > 0 {
                    print("\(indent)   Children count: \(childArray.count)")
                    for child in childArray {
                        findTextEditorElements(from: child, depth: depth + 1)
                    }
                }
            }
        }
    }
    
    func deepSearchForSelection(element: AXUIElement, maxDepth: Int, currentDepth: Int = 0) -> String? {
        guard currentDepth < maxDepth else { return nil }
        
        // Try getting selection from current element
        if let text = tryGetSelectedTextDirect(from: element) {
            return text
        }
        
        // Get all children and search recursively
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childElements = children as? [AXUIElement] {
                for child in childElements {
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
                    let roleStr = role as? String ?? "Unknown"
                    
                    if currentDepth == 0 {
                        print("Searching child role: \(roleStr) at depth \(currentDepth)")
                    }
                    
                    // Recursively search children
                    if let text = deepSearchForSelection(element: child, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                        return text
                    }
                }
            }
        }
        
        return nil
    }
    
    func tryAlternativeAccessibilityMethods(element: AXUIElement) -> String? {
        // Get all available attributes
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
            if let names = attributeNames as? [String] {
                print("Available attributes: \(names)")
                
                // Try all text-related attributes
                let textAttributes = ["AXSelectedText", "AXValue", "AXDocument", "AXTextContent", "AXContents", "AXText"]
                
                for attr in textAttributes {
                    if names.contains(attr) {
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success {
                            if let text = value as? String, !text.isEmpty {
                                // Check if this might be selected text
                                if attr == "AXSelectedText" || text.count < 1000 {
                                    print("Found text via \(attr): \(text)")
                                    return text
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    func tryGetSelectedTextDirect(from element: AXUIElement) -> String? {
        // Method 1: Direct selected text
        var selectedText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success {
            if let text = selectedText as? String, !text.isEmpty {
                print("Found direct selected text: \(text)")
                return text
            }
        }
        
        // Method 2: Check if element has selection range
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            if let range = selectedRange, CFGetTypeID(range) == AXValueGetTypeID() {
                let axValue = range as! AXValue
                var cfRange = CFRange()
                if AXValueGetValue(axValue, .cfRange, &cfRange) && cfRange.length > 0 {
                    print("Found non-zero selection range: location=\(cfRange.location), length=\(cfRange.length)")
                    
                    // Try getting the text using different value attributes
                    let valueAttributes = ["AXValue", "AXDocument", "AXTextContent"]
                    for attr in valueAttributes {
                        var fullText: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, attr as CFString, &fullText) == .success {
                            if let text = fullText as? String, text.count >= cfRange.location + cfRange.length {
                                let startIndex = max(0, cfRange.location)
                                let endIndex = min(text.count, cfRange.location + cfRange.length)
                                
                                if startIndex < endIndex {
                                    let start = text.index(text.startIndex, offsetBy: startIndex)
                                    let end = text.index(text.startIndex, offsetBy: endIndex)
                                    let selectedText = String(text[start..<end])
                                    if !selectedText.isEmpty {
                                        print("Extracted selected text via \(attr): \(selectedText)")
                                        return selectedText
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    func tryGetSelectedTextFromChildren(element: AXUIElement) -> String? {
        print("Trying to get selected text from child elements...")
        
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let childElements = children as? [AXUIElement] {
                for child in childElements {
                    if let text = tryGetSelectedText(from: child) {
                        return text
                    }
                }
            }
        }
        
        return nil
    }
    
    func tryGetTextViaCopy() -> String? {
        print("Trying to get text via copy command...")
        
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
        
        // Restore original clipboard if we didn't get anything new
        if newContent == nil || newContent?.isEmpty == true || newContent == originalContent {
            if let original = originalContent {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
            return nil
        }
        
        print("Got text via copy: \(newContent ?? "")")
        return newContent
    }
    
    func analyzeElement(_ element: AXUIElement, depth: Int) {
        // Increase recursion depth for complete analysis, but still have a safety limit
        guard depth < 10 else {
            print("Reached maximum analysis depth")
            return
        }
        
        let indent = String(repeating: "  ", count: depth)
        
        // Get element role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = role as? String ?? "Unknown"
        
        // Get element description
        var roleDescription: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescription)
        let roleDesc = roleDescription as? String ?? ""
        
        // Get element title
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let titleString = title as? String ?? ""
        
        print("\(indent)Element: \(roleString) (\(roleDesc)) \(titleString.isEmpty ? "" : "- \(titleString)")")
        
        // Show ALL attributes for Sublime Text analysis
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
            if let names = attributeNames as? [String] {
                print("\(indent)  Available attributes: \(names)")
                
                // Show values for key attributes
                let keyAttributes = ["AXSelectedText", "AXSelectedTextRange", "AXValue", "AXRole", "AXDescription", "AXDocument", "AXTextContent", "AXContents", "AXText", "AXInsertionPointLineNumber"]
                
                for name in names where keyAttributes.contains(name) {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success {
                        if let stringValue = value as? String, !stringValue.isEmpty {
                            print("\(indent)    \(name): \(stringValue.prefix(100))...")
                        } else if name == "AXSelectedTextRange" {
                            if let range = value, CFGetTypeID(range) == AXValueGetTypeID() {
                                let axValue = range as! AXValue
                                var cfRange = CFRange()
                                if AXValueGetValue(axValue, .cfRange, &cfRange) {
                                    print("\(indent)    \(name): location=\(cfRange.location), length=\(cfRange.length)")
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
                if childArray.count > 0 {
                    print("\(indent)  Children count: \(childArray.count)")
                    for (index, child) in childArray.enumerated() {
                        print("\(indent)  Child \(index):")
                        analyzeElement(child, depth: depth + 1)
                    }
                }
            }
        }
        
        // For elements that might contain text editors, force deeper exploration
        if roleString.contains("Group") || roleString.contains("ScrollArea") || roleString.contains("SplitGroup") {
            print("\(indent)  --> Potentially contains text editor, exploring deeper...")
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 先確保舊窗口完全關閉
            if let oldWindow = self.popupWindow {
                oldWindow.close()
                self.popupWindow = nil
            }
            
            // 短暫延遲確保清理完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                guard let self = self else { return }
                
                print("Creating new popup window...")
                let mouseLocation = NSEvent.mouseLocation
                let menuWindow = PopupMenuWindow(selectedText: text)
                
                var origin = NSPoint(x: mouseLocation.x - 60, y: mouseLocation.y - 100)
                
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    if origin.x + 120 > screenFrame.maxX {
                        origin.x = screenFrame.maxX - 120
                    }
                    if origin.x < screenFrame.minX {
                        origin.x = screenFrame.minX
                    }
                    if origin.y < screenFrame.minY {
                        origin.y = mouseLocation.y + 20
                    }
                }
                
                menuWindow.setFrameOrigin(origin)
                menuWindow.makeKeyAndOrderFront(nil)
                
                self.popupWindow = menuWindow
                print("Popup window created and displayed")
            }
        }
    }
    
    func hidePopupMenu() {
        DispatchQueue.main.async {
            if let window = self.popupWindow {
                window.close()
            }
            self.popupWindow = nil
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
    }
}

class PopupMenuWindow: NSWindow {
    let selectedText: String
    var timeoutTimer: Timer?
    
    init(selectedText: String) {
        self.selectedText = selectedText
        
        let contentRect = NSRect(x: 0, y: 0, width: 120, height: 80)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupButtons()
        setupTimeout()
    }
    
    func setupTimeout() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                print("Timer triggered, preparing to close window...")
                self?.closeAndNotify()
            }
        }
    }
    
    override func close() {
        print("close() called")
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        super.close()
    }
    
    deinit {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    func setupWindow() {
        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        hasShadow = true
        
        guard let currentContentView = contentView else { return }
        
        let visualEffect = NSVisualEffectView(frame: currentContentView.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.autoresizingMask = [.width, .height]
        
        contentView = visualEffect
    }
    
    func setupButtons() {
        guard let contentView = contentView else { return }
        
        let saveButton = NSButton(frame: NSRect(x: 10, y: 45, width: 100, height: 25))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        
        let copyButton = NSButton(frame: NSRect(x: 10, y: 10, width: 100, height: 25))
        copyButton.title = "Copy"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyAction)
        
        contentView.addSubview(saveButton)
        contentView.addSubview(copyButton)
    }
    
    @objc func saveAction() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "selected_text.txt"
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                do {
                    try selectedText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save: \(error)")
                }
            }
        }
        
        closeAndNotify()
    }
    
    @objc func copyAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
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
        print("closeAndNotify called")
        
        // Clean up timer first
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Notify AppDelegate to clear reference
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if appDelegate.popupWindow === self {
                print("Clearing AppDelegate popupWindow reference")
                appDelegate.popupWindow = nil
            }
        }
        
        // Hide window directly instead of closing
        print("Hiding window")
        self.orderOut(nil)
        
        // Delayed close to avoid crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            print("Delayed window close")
            self?.performClose(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()