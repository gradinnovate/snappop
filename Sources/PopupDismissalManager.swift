import Cocoa

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