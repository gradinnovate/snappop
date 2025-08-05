import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popupWindow: NSWindow?
    var eventTap: CFMachPort?
    
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
        let eventMask = (1 << CGEventType.leftMouseUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                appDelegate.handleMouseUp(event: event)
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
    
    func handleMouseUp(event: CGEvent) {
        print("Mouse up event triggered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            print("Preparing to get selected text...")
            guard let self = self else {
                print("AppDelegate has been released")
                return
            }
            self.getSelectedText()
        }
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
        
        // Analyze element details
        analyzeElement(axElement, depth: 0)
        
        // Try multiple methods to get selected text
        if let text = tryGetSelectedText(from: axElement) {
            return text
        }
        
        print("All methods failed to get selected text")
        return nil
    }
    
    func analyzeElement(_ element: AXUIElement, depth: Int) {
        // Limit recursion depth to avoid crashes
        guard depth < 3 else {
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
        
        print("\(indent)Element: \(roleString) (\(roleDesc))")
        
        // Only show key attributes to avoid too much output
        let keyAttributes = ["AXSelectedText", "AXValue", "AXRole", "AXDescription", "AXDocument"]
        
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success {
            if let names = attributeNames as? [String] {
                for name in names where keyAttributes.contains(name) {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success {
                        if let stringValue = value as? String, !stringValue.isEmpty {
                            print("\(indent)  \(name): \(stringValue)")
                        }
                    }
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