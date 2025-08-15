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
    private var lastDoubleClickTime: CFTimeInterval = 0  // Prevent rapid double-clicks
    
    // Segfault fix: Prevent multiple concurrent popup creations
    private var isCreatingPopup: Bool = false
    private let popupCreationQueue = DispatchQueue(label: "com.snappop.popup", qos: .userInteractive)
    
    // Monitoring control
    private var isMonitoringEnabled: Bool = true
    private var isMonitoringPaused: Bool = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for existing instances and prevent duplicates
        let runningApps = NSWorkspace.shared.runningApplications
        let snapPopInstances = runningApps.filter { app in
            (app.bundleIdentifier == "com.gradinnovate.snappop" || 
             app.localizedName == "SnapPop") && 
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        if !snapPopInstances.isEmpty {
            os_log("Another SnapPop instance is already running, exiting...", log: .lifecycle, type: .info)
            NSApplication.shared.terminate(nil)
            return
        }
        
        // Always setup status item first
        setupStatusItem()
        
        if !checkAccessibilityPermissions() {
            // Show alert on first launch or when permission is revoked
            showAccessibilityAlert()
            return
        }
        
        // Only setup monitoring if we have permissions
        setupTextSelectionMonitoring()
        setupEnhancedMonitoring()
        
        os_log("SnapPop launched successfully with full functionality", log: .lifecycle, type: .info)
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
        alert.messageText = "SnapPop Needs Accessibility Permission"
        alert.informativeText = """
        SnapPop requires accessibility permission to detect text selections across all applications.
        
        Steps to grant permission:
        1. Click "Open System Preferences" below
        2. Unlock the settings if needed (click the lock icon)
        3. Find "SnapPop" in the list and check the box next to it
        4. Restart SnapPop
        
        This permission allows SnapPop to monitor mouse events and read selected text.
        """
        
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Without Permission")
        
        // Set alert as critical to ensure it appears on top
        alert.alertStyle = .critical
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Accessibility panel
            openAccessibilityPreferences()
            
            // Start a timer to check periodically if permission is granted
            startPermissionMonitoring()
            
        } else if response == .alertSecondButtonReturn {
            // User chose to quit
            NSApplication.shared.terminate(nil)
            
        } else if response == .alertThirdButtonReturn {
            // User chose to continue without permission
            showLimitedFunctionalityWarning()
        }
    }
    
    private func openAccessibilityPreferences() {
        // Try multiple methods to open accessibility preferences
        let accessibilityURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preferences.security.privacy?Privacy_Accessibility"
        ]
        
        var opened = false
        for urlString in accessibilityURLs {
            if let url = URL(string: urlString) {
                if NSWorkspace.shared.open(url) {
                    opened = true
                    break
                }
            }
        }
        
        if !opened {
            // Fallback: open general Security & Privacy preferences
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
            
            // Show additional instructions
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let instructionAlert = NSAlert()
                instructionAlert.messageText = "Manual Navigation Required"
                instructionAlert.informativeText = """
                Please navigate manually to:
                Privacy → Accessibility
                
                Then add SnapPop to the list and enable it.
                """
                instructionAlert.runModal()
            }
        }
    }
    
    private func startPermissionMonitoring() {
        // Check every 3 seconds if permission is granted
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.checkAccessibilityPermissions() {
                timer.invalidate()
                self.onAccessibilityPermissionGranted()
            }
        }
    }
    
    private func onAccessibilityPermissionGranted() {
        let successAlert = NSAlert()
        successAlert.messageText = "Permission Granted!"
        successAlert.informativeText = "SnapPop can now monitor text selections. The application will start working immediately."
        successAlert.addButton(withTitle: "Great!")
        successAlert.alertStyle = .informational
        successAlert.runModal()
        
        // Initialize monitoring now that we have permission
        setupTextSelectionMonitoring()
        setupEnhancedMonitoring()
        
        os_log("Accessibility permission granted, monitoring started", log: .lifecycle, type: .info)
    }
    
    private func showLimitedFunctionalityWarning() {
        let warningAlert = NSAlert()
        warningAlert.messageText = "Limited Functionality"
        warningAlert.informativeText = """
        Without accessibility permission, SnapPop cannot:
        • Detect text selections in other applications
        • Show popup menus for selected text
        • Monitor mouse events globally
        
        You can grant permission later through the status bar menu.
        """
        warningAlert.addButton(withTitle: "OK")
        warningAlert.alertStyle = .warning
        warningAlert.runModal()
        
        // Still setup status bar but with limited functionality
        setupStatusItem()
        
        os_log("Running with limited functionality - no accessibility permission", log: .lifecycle, type: .default)
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.menu = createStatusMenu()
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: "SnapPop")
        }
        
        // Also set initial icon state
        updateStatusBarIcon()
    }
    
    func createStatusMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Status information
        let statusTitle = isMonitoringPaused ? "SnapPop (Paused)" : "SnapPop (Active)"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Pause/Resume monitoring (always show, regardless of permission status)
        let monitoringAction = isMonitoringPaused ? "▶️ Resume Monitoring" : "⏸️ Pause Monitoring"
        let monitoringItem = NSMenuItem(title: monitoringAction, action: #selector(toggleMonitoring), keyEquivalent: "")
        monitoringItem.target = self
        
        // Disable if no accessibility permission
        if !checkAccessibilityPermissions() {
            monitoringItem.isEnabled = false
        }
        
        menu.addItem(monitoringItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Start at login
        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isStartAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Accessibility permission status
        if !checkAccessibilityPermissions() {
            let permissionItem = NSMenuItem(title: "⚠️ Grant Accessibility Permission", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
            permissionItem.target = self
            menu.addItem(permissionItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Configuration
        let configItem = NSMenuItem(title: "Detection Settings...", action: #selector(showDetectionSettings), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About
        let aboutItem = NSMenuItem(title: "About SnapPop", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit SnapPop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    func refreshStatusMenu() {
        // Update the menu with current state
        statusItem?.menu = createStatusMenu()
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
    
    // MARK: - Enhanced Menu Actions
    
    @objc func toggleMonitoring() {
        // Check accessibility permission first
        guard checkAccessibilityPermissions() else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "SnapPop needs accessibility permission to monitor text selections. Please grant permission first."
            alert.addButton(withTitle: "Grant Permission")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                requestAccessibilityPermission()
            }
            return
        }
        
        isMonitoringPaused.toggle()
        
        if isMonitoringPaused {
            // Disable event monitoring
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            // Hide any existing popup
            hidePopupMenu()
            // Update status bar icon to indicate paused state
            updateStatusBarIcon()
            os_log("Text selection monitoring paused", log: .lifecycle, type: .info)
            
            // Show confirmation
            showTemporaryNotification("Monitoring Paused", "Text selection detection is now disabled.")
            
        } else {
            // Re-enable event monitoring
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                // Re-setup monitoring if needed
                setupTextSelectionMonitoring()
                setupEnhancedMonitoring()
            }
            updateStatusBarIcon()
            os_log("Text selection monitoring resumed", log: .lifecycle, type: .info)
            
            // Show confirmation
            showTemporaryNotification("Monitoring Resumed", "Text selection detection is now active.")
        }
        
        // Refresh the menu to update the button text and state
        refreshStatusMenu()
    }
    
    private func showTemporaryNotification(_ title: String, _ message: String) {
        // Show a brief, non-blocking notification
        os_log("%{public}@: %{public}@", log: .lifecycle, type: .info, title, message)
        
        // Update status bar tooltip to show the notification
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.toolTip = "\(title): \(message)"
            
            // Clear tooltip after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.statusItem?.button?.toolTip = "SnapPop - Text Selection Helper"
            }
        }
    }
    
    @objc func toggleStartAtLogin() {
        let currentStatus = isStartAtLoginEnabled()
        os_log("Toggle start at login - current status: %{public}@", log: .lifecycle, type: .info, currentStatus ? "enabled" : "disabled")
        
        if currentStatus {
            os_log("Attempting to disable start at login", log: .lifecycle, type: .info)
            disableStartAtLogin()
        } else {
            os_log("Attempting to enable start at login", log: .lifecycle, type: .info)
            enableStartAtLogin()
        }
        
        // Refresh menu to update the checkmark state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let newStatus = self?.isStartAtLoginEnabled() ?? false
            os_log("After toggle - new status: %{public}@", log: .lifecycle, type: .info, newStatus ? "enabled" : "disabled")
            self?.refreshStatusMenu()
        }
    }
    
    @objc func requestAccessibilityPermission() {
        showAccessibilityAlert()
    }
    
    @objc func showDetectionSettings() {
        let alert = NSAlert()
        alert.messageText = "Detection Settings"
        
        // Get current configuration
        let config = EasydictConfiguration.self
        let currentMode = config.detectionMode.displayName
        let currentSensitivity = config.sensitivity
        
        alert.informativeText = """
        Current Detection Mode: \(currentMode)
        Sensitivity: \(String(format: "%.1f", currentSensitivity))
        
        Available Modes:
        • Easydict (Pure Event Sequence) - Most responsive
        • Hybrid (Easydict + Validation) - Balanced approach  
        • Traditional (Distance + Time) - Most conservative
        • Adaptive (Auto-Select Best) - Smart selection
        
        Use command line to change settings:
        defaults write com.gradinnovate.snappop SnapPopDetectionMode "easydict"
        defaults write com.gradinnovate.snappop SnapPopSensitivity 1.5
        """
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset to Default")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // Reset to default settings
            config.detectionMode = .easydictOnly
            config.sensitivity = 1.0
            config.logCurrentConfiguration()
        }
    }
    
    private func updateStatusBarIcon() {
        let iconName = isMonitoringPaused ? "pause.circle" : "selection.pin.in.out"
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SnapPop")
    }
    
    // MARK: - Login Item Management
    
    private func isStartAtLoginEnabled() -> Bool {
        // Check if the launchd plist exists in user's LaunchAgents directory
        let launchAgentsPath = NSHomeDirectory() + "/Library/LaunchAgents/com.gradinnovate.snappop.plist"
        return FileManager.default.fileExists(atPath: launchAgentsPath)
    }
    
    private func enableStartAtLogin() {
        let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
        let targetPlistPath = launchAgentsDir + "/com.gradinnovate.snappop.plist"
        
        do {
            // Create LaunchAgents directory if it doesn't exist
            try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
            
            // Always create plist content manually to ensure correct paths
            createLoginPlist(at: targetPlistPath)
            
            // Check if there's already a running instance and prevent duplicate launch
            let runningApps = NSWorkspace.shared.runningApplications
            let snapPopRunning = runningApps.contains { app in
                app.bundleIdentifier == "com.gradinnovate.snappop" || 
                app.localizedName == "SnapPop"
            }
            
            if snapPopRunning {
                // If SnapPop is already running, just register the plist without loading
                os_log("SnapPop already running, plist created but not loaded to prevent duplicate", log: .lifecycle, type: .info)
                showTemporaryNotification("Start at Login Enabled", "Will start when you log in (current instance continues)")
            } else {
                // Safe to load since no instance is running
                let task = Process()
                task.launchPath = "/bin/launchctl"
                task.arguments = ["load", targetPlistPath]
                
                let pipe = Pipe()
                task.standardError = pipe
                task.launch()
                task.waitUntilExit()
                
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                if task.terminationStatus == 0 {
                    os_log("Start at login enabled successfully", log: .lifecycle, type: .info)
                    showTemporaryNotification("Start at Login Enabled", "SnapPop will start when you log in")
                } else {
                    os_log("launchctl load failed: %{public}@", log: .lifecycle, type: .error, errorOutput)
                    showTemporaryNotification("Warning", "Start at login enabled but may need restart")
                }
            }
            
        } catch {
            os_log("Failed to enable start at login: %{public}@", log: .lifecycle, type: .error, error.localizedDescription)
            
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to enable start at login: \(error.localizedDescription)"
            alert.runModal()
        }
    }
    
    private func disableStartAtLogin() {
        let targetPlistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.gradinnovate.snappop.plist"
        
        // Check if file exists first
        guard FileManager.default.fileExists(atPath: targetPlistPath) else {
            os_log("Start at login plist not found, already disabled", log: .lifecycle, type: .info)
            showTemporaryNotification("Already Disabled", "Start at login was not enabled")
            return
        }
        
        do {
            // Unload the launch agent
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = ["unload", targetPlistPath]
            
            let pipe = Pipe()
            task.standardError = pipe
            task.launch()
            task.waitUntilExit()
            
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Remove plist file regardless of unload result
            try FileManager.default.removeItem(atPath: targetPlistPath)
            
            if task.terminationStatus == 0 || errorOutput.contains("Could not find specified service") {
                os_log("Start at login disabled successfully", log: .lifecycle, type: .info)
                showTemporaryNotification("Start at Login Disabled", "SnapPop will not start automatically")
            } else {
                os_log("launchctl unload warning: %{public}@", log: .lifecycle, type: .default, errorOutput)
                showTemporaryNotification("Start at Login Disabled", "Plist removed, may need logout/login")
            }
            
        } catch {
            os_log("Failed to disable start at login: %{public}@", log: .lifecycle, type: .error, error.localizedDescription)
            
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to disable start at login: \(error.localizedDescription)"
            alert.runModal()
        }
    }
    
    private func createLoginPlist(at path: String) {
        let appPath = Bundle.main.bundlePath
        let executablePath = appPath + "/Contents/MacOS/SnapPop"
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.gradinnovate.snappop</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LaunchOnlyOnce</key>
            <true/>
        </dict>
        </plist>
        """
        
        try? plistContent.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
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
        // Check if monitoring is paused
        guard !isMonitoringPaused else { return }
        
        mouseDownLocation = event.location
        mouseDownTime = CFAbsoluteTimeGetCurrent()
        debugPrint("Mouse down at location: \(mouseDownLocation!)")
    }
    
    func handleMouseUp(event: CGEvent) {
        // Check if monitoring is paused
        guard !isMonitoringPaused else { return }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        let mouseUpLocation = event.location
        
        // Enhanced Feature 2: Double-click detection (ALWAYS check first, regardless of detection mode)
        let doubleClickDetected = detectDoubleClick(at: mouseUpLocation, time: currentTime)
        
        if doubleClickDetected {
            debugPrint("Double-click detected at \(mouseUpLocation) - triggering text selection")
            
            // Enhanced segfault protection for double-click
            if isCreatingPopup {
                os_log("Popup creation in progress, ignoring double-click", log: .popup, type: .info)
                resetTrackingVariables()
                return
            }
            
            // CRITICAL: More aggressive popup state checking
            if let existingPopup = popupWindow {
                if existingPopup.isVisible {
                    debugPrint("🔧 DEBUG: Popup visible, ignoring double-click to prevent segfault")
                    resetTrackingVariables()
                    return
                }
                
                // Force close any existing popup immediately
                debugPrint("🔧 DEBUG: Force closing existing popup for double-click")
                popupWindow = nil
                existingPopup.orderOut(nil)
            }
            
            // Set creation flag immediately to prevent race conditions
            isCreatingPopup = true
            
            // Increased delay for double-click to prevent rapid-fire segfaults
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                debugPrint("Preparing to get selected text from double-click...")
                self?.getSelectedTextForDoubleClick()
            }
            return
        }
        
        // Check detection mode after double-click handling
        if EasydictEventMonitor.shouldUseEasydictDetection() {
            os_log("Using Easydict detection - skipping traditional validation", log: .textSelection, type: .info)
            // Easydict monitor handles drag-based selection via delayed validation
            resetTrackingVariables()
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
        debugPrint("🔧 DEBUG: getSelectedTextForDoubleClick called")
        
        // CRITICAL: Additional safety checks for double-click
        if isCreatingPopup {
            debugPrint("🔧 DEBUG: Popup creation already in progress, skipping double-click text selection")
            isCreatingPopup = false // Reset flag to prevent stuck state
            return
        }
        
        // Check if popup already exists and is visible
        if let existingPopup = popupWindow, existingPopup.isVisible {
            debugPrint("🔧 DEBUG: Popup already visible, ignoring double-click to prevent segfault")
            return
        }
        
        // Use the same thread-safe approach as regular text selection
        popupCreationQueue.async { [weak self] in
            debugPrint("🔧 DEBUG: Double-click text extraction in queue")
            guard let self = self else { 
                debugPrint("🔧 DEBUG: self is nil in double-click queue")
                return 
            }
            
            // Double-check creation flag in queue
            if self.isCreatingPopup {
                debugPrint("🔧 DEBUG: Creation flag set in queue, skipping double-click")
                return
            }
            
            // Set creation flag to prevent concurrent access
            self.isCreatingPopup = true
            
            if let text = self.getSelectedTextViaAccessibility(), !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                debugPrint("🔧 DEBUG: Double-click text selection successful: \(text.prefix(50))...")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { 
                        debugPrint("🔧 DEBUG: self is nil in double-click main async")
                        return 
                    }
                    self.showPopupMenu(for: text)
                }
            } else {
                debugPrint("🔧 DEBUG: Double-click detected but no text selected")
                // Reset flag if no text found
                DispatchQueue.main.async { [weak self] in
                    self?.isCreatingPopup = false
                }
            }
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
    
    // Track window closing state to prevent race conditions
    private var isClosing: Bool = false
    
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
    
    // Module 5: Enhanced dismissal setup with safety checks
    func setupEnhancedDismissal() {
        // Prevent creating dismissal manager if window is already being closed
        guard !isClosing else {
            debugPrint("🔧 DEBUG: Window is closing, skipping dismissal manager setup")
            return
        }
        
        // Only create dismissal manager if one doesn't already exist
        if dismissalManager == nil {
            debugPrint("🔧 DEBUG: Creating PopupDismissalManager")
            dismissalManager = PopupDismissalManager(popupWindow: self)
        } else {
            debugPrint("🔧 DEBUG: PopupDismissalManager already exists, skipping creation")
        }
    }
    
    override func close() {
        print("close() called")
        
        // Thread safety for close operation
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        // Prevent multiple close calls
        guard !isVisible || alphaValue > 0 else {
            print("Window already closed, skipping")
            return
        }
        
        // CRITICAL: Clean up dismissal manager FIRST to remove event monitors
        if let manager = dismissalManager {
            manager.cleanup()
            dismissalManager = nil
        }
        
        // Clean up timer safely
        if let timer = timeoutTimer {
            timer.invalidate()
            timeoutTimer = nil
        }
        
        // Clear buttons array to break potential retain cycles
        buttons.removeAll()
        
        // Use orderOut first for safer window closing
        self.orderOut(nil)
        
        // Then call super.close() on main thread with delay to ensure cleanup
        DispatchQueue.main.async { [weak self] in
            self?.performSuperClose()
        }
    }
    
    private func performSuperClose() {
        guard let window = self as NSWindow? else { return }
        if window.isVisible {
            super.close()
        }
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
        // Set closing flag to prevent race conditions
        isClosing = true
        
        // Clean up timer first
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Clean up dismissal manager safely before window closure
        if let manager = dismissalManager {
            debugPrint("🔧 DEBUG: Cleaning up dismissal manager before window closure")
            manager.cleanup()
            dismissalManager = nil
        }
        
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