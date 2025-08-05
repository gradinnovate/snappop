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
            self.showPopupMenu(for: text)
        }
    }
    
    func getSelectedTextViaAccessibility() -> String? {
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
        
        // Handle Sublime Text directly with CMD+C (known to not expose selection via AX APIs)
        if applicationName.contains("Sublime Text") || runningAppName.contains("Sublime Text") {
            return tryGetTextViaCopy()
        }
        
        // Try standard accessibility methods for other applications
        if let text = tryGetSelectedText(from: axElement) {
            return text
        }
        
        // Try CMD+C as fallback for applications that don't expose selection via AX APIs
        return tryGetTextViaCopy()
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
                
                let mouseLocation = NSEvent.mouseLocation
                let menuWindow = PopupMenuWindow(selectedText: text)
                
                // Position according to UI spec: below selection, or above if no space
                var origin = NSPoint(x: mouseLocation.x - 130, y: mouseLocation.y - 60)
                
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let windowWidth: CGFloat = 260
                    
                    // Horizontal positioning
                    if origin.x + windowWidth > screenFrame.maxX {
                        origin.x = screenFrame.maxX - windowWidth
                    }
                    if origin.x < screenFrame.minX {
                        origin.x = screenFrame.minX
                    }
                    
                    // Vertical positioning - below by default, above if no space
                    if origin.y < screenFrame.minY {
                        origin.y = mouseLocation.y + 20
                    }
                }
                
                menuWindow.setFrameOrigin(origin)
                
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
    
    init(selectedText: String) {
        self.selectedText = selectedText
        
        // Calculate dynamic width based on buttons (4 buttons + separators + padding)
        // Each button ~60px, 3 separators 1px each, padding 20px total
        let contentRect = NSRect(x: 0, y: 0, width: 260, height: 40)
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
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
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
        let buttonWidth: CGFloat = 60
        let separatorWidth: CGFloat = 1
        let leftPadding: CGFloat = 10
        
        // Create buttons with proper styling
        let cutButton = createButton(title: "Cut", action: #selector(cutAction))
        let copyButton = createButton(title: "Copy", action: #selector(copyAction))  
        let pasteButton = createButton(title: "Paste", action: #selector(pasteAction))
        let searchButton = createButton(title: "🔍", action: #selector(searchAction))
        
        buttons = [cutButton, copyButton, pasteButton, searchButton]
        
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
    
    @objc func cutAction() {
        // Copy to clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
        
        // Simulate delete key to cut the selected text
        let source = CGEventSource(stateID: .hidSystemState)
        let deleteEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true) // Delete key
        let deleteUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
        
        deleteEvent?.post(tap: .cghidEventTap)
        deleteUpEvent?.post(tap: .cghidEventTap)
        
        closeAndNotify()
    }
    
    @objc func copyAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
        closeAndNotify()
    }
    
    @objc func pasteAction() {
        // Simulate CMD+V to paste
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        keyDownEvent?.flags = .maskCommand
        keyUpEvent?.flags = .maskCommand
        
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
        
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
            }
        }
        
        // Add fade out animation according to spec (100ms)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            // Delayed close to avoid crashes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.performClose(nil)
            }
        })
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()