import Cocoa
import ApplicationServices
import os.log

// MARK: - Window Operation Detector for Multi-layered Monitoring
class WindowOperationDetector {
    
    static let shared = WindowOperationDetector()
    
    // Window state tracking
    private var windowObservers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var isWindowOperationInProgress = false
    private var lastWindowOperationTime: CFTimeInterval = 0
    
    // Application state tracking
    private var frontmostApplication: NSRunningApplication?
    private var applicationWindows: Set<CGWindowID> = []
    private var lastWindowListUpdate: CFTimeInterval = 0
    
    private init() {
        setupMonitoring()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    func setupMonitoring() {
        setupWindowNotifications()
        setupWorkspaceNotifications()
        updateApplicationWindows()
    }
    
    private func setupWindowNotifications() {
        // Monitor various window operations that could interfere with text selection
        let windowNotifications: [NSNotification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        
        for notification in windowNotifications {
            let observer = NotificationCenter.default.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleWindowNotification(notification)
            }
            windowObservers.append(observer)
        }
        
        os_log("Window notifications setup complete", log: .validation, type: .info)
    }
    
    private func setupWorkspaceNotifications() {
        // Monitor application activation changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationActivation(notification)
        }
        
        os_log("Workspace notifications setup complete", log: .validation, type: .info)
    }
    
    // MARK: - Event Handlers
    
    private func handleWindowNotification(_ notification: Notification) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Mark window operation as in progress
        isWindowOperationInProgress = true
        lastWindowOperationTime = currentTime
        
        // Log the specific operation type
        let operationType = notification.name.rawValue.replacingOccurrences(of: "NSWindow", with: "")
        os_log("Window operation detected: %{public}@", log: .validation, type: .info, operationType)
        
        // Update window list for better tracking
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.updateApplicationWindows()
        }
        
        // Auto-reset flag after a reasonable delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self = self, (CFAbsoluteTimeGetCurrent() - self.lastWindowOperationTime) >= 0.5 {
                self.isWindowOperationInProgress = false
            }
        }
    }
    
    private func handleApplicationActivation(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        // Update frontmost application
        frontmostApplication = app
        
        os_log("Application activated: %{public}@", log: .validation, type: .info, app.localizedName ?? "Unknown")
        
        // Update window list for new application
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.updateApplicationWindows()
        }
        
        // Clear any ongoing window operation state when switching apps
        isWindowOperationInProgress = false
    }
    
    // MARK: - Window List Management
    
    private func updateApplicationWindows() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Throttle updates to avoid excessive system calls
        guard (currentTime - lastWindowListUpdate) > 1.0 else { return }
        lastWindowListUpdate = currentTime
        
        // Get list of windows for current application
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        
        let appWindows = windowList.compactMap { windowInfo -> CGWindowID? in
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == frontmost.processIdentifier,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                return nil
            }
            return windowID
        }
        
        applicationWindows = Set(appWindows)
    }
    
    // MARK: - Public Detection Methods
    
    func isWindowOperationDetected() -> Bool {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Check recent window operations
        if isWindowOperationInProgress && (currentTime - lastWindowOperationTime) < 0.5 {
            return true
        }
        
        // Check for file operations by monitoring window count changes
        let previousWindowCount = applicationWindows.count
        updateApplicationWindows()
        let currentWindowCount = applicationWindows.count
        
        if abs(currentWindowCount - previousWindowCount) > 0 {
            os_log("Window count changed: %d -> %d", log: .validation, type: .info, 
                   previousWindowCount, currentWindowCount)
            return true
        }
        
        // Auto-reset if enough time has passed
        if (currentTime - lastWindowOperationTime) > 1.0 {
            isWindowOperationInProgress = false
        }
        
        return false
    }
    
    func isFileOperationLikely(dragDistance: Double, dragDuration: CFTimeInterval) -> Bool {
        // File operations typically involve:
        // 1. Longer drag distances
        // 2. Reasonable duration (not too fast, not too slow)
        // 3. Often accompanied by window operations
        
        let isLongDistance = dragDistance > 150
        let isReasonableDuration = dragDuration > 0.2 && dragDuration < 3.0
        let hasRecentWindowOperation = isWindowOperationDetected()
        
        if isLongDistance && isReasonableDuration {
            if hasRecentWindowOperation {
                return true  // High confidence
            }
            return dragDistance > 300  // Very long drags without window ops might still be file ops
        }
        
        return false
    }
    
    func shouldSuppressPopup(for gestureData: GestureData) -> Bool {
        // Comprehensive check combining multiple signals
        
        if isWindowOperationDetected() {
            os_log("Suppressing popup: window operation detected", log: .validation, type: .info)
            return true
        }
        
        if isFileOperationLikely(dragDistance: gestureData.distance, dragDuration: gestureData.duration) {
            os_log("Suppressing popup: file operation likely", log: .validation, type: .info)
            return true
        }
        
        // Check for window resize patterns (starts near edges, significant movement)
        if isWindowResizeLikely(mouseDown: gestureData.mouseDown, distance: gestureData.distance) {
            os_log("Suppressing popup: window resize likely", log: .validation, type: .info)
            return true
        }
        
        return false
    }
    
    private func isWindowResizeLikely(mouseDown: CGPoint, distance: Double) -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let screenFrame = screen.visibleFrame
        let edgeThreshold: CGFloat = 40
        
        let nearEdge = mouseDown.x < screenFrame.minX + edgeThreshold ||
                      mouseDown.x > screenFrame.maxX - edgeThreshold ||
                      mouseDown.y < screenFrame.minY + edgeThreshold ||
                      mouseDown.y > screenFrame.maxY - edgeThreshold
        
        return nearEdge && distance > 30
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove all window observers
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        
        // Remove workspace observer
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        
        os_log("WindowOperationDetector cleanup complete", log: .validation, type: .info)
    }
}

// MARK: - Supporting Types

struct GestureData {
    let mouseDown: CGPoint
    let mouseUp: CGPoint
    let duration: CFTimeInterval
    let distance: Double
    
    init(mouseDown: CGPoint, mouseUp: CGPoint, duration: CFTimeInterval, distance: Double) {
        self.mouseDown = mouseDown
        self.mouseUp = mouseUp
        self.duration = duration
        self.distance = distance
    }
}