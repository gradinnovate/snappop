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
        
        // Enhanced thread safety with additional checks
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        guard !isCleanedUp else {
            debugPrint("🔧 DEBUG: Already cleaned up, skipping...")
            return
        }
        
        isCleanedUp = true
        isDismissing = false
        
        // CRITICAL: Store monitor references locally before clearing to prevent race conditions
        let scrollMonitorToRemove = scrollMonitor
        let mouseMoveMonitorToRemove = mouseMoveMonitor
        let keyMonitorToRemove = keyMonitor
        
        // Clear all references immediately
        scrollMonitor = nil
        mouseMoveMonitor = nil
        keyMonitor = nil
        popupWindow = nil
        
        // Remove monitors safely with local references
        DispatchQueue.main.async {
            if let monitor = scrollMonitorToRemove {
                debugPrint("🔧 DEBUG: Removing scroll monitor")
                NSEvent.removeMonitor(monitor)
            }
            
            if let monitor = mouseMoveMonitorToRemove {
                debugPrint("🔧 DEBUG: Removing mouse move monitor")  
                NSEvent.removeMonitor(monitor)
            }
            
            if let monitor = keyMonitorToRemove {
                debugPrint("🔧 DEBUG: Removing key monitor")
                NSEvent.removeMonitor(monitor)
            }
            
            debugPrint("🔧 DEBUG: PopupDismissalManager cleanup completed safely")
        }
    }
}