import Cocoa
import ApplicationServices
import os.log

// MARK: - Easydict-style Event Monitor
// Pure event sequence detection with delayed validation strategy

class EasydictEventMonitor {
    
    // Constants matching Easydict exactly
    static let kDelayGetSelectedTextTime: TimeInterval = 0.1
    static let kExpandedRadiusValue: CGFloat = 120
    static let kRecordEventCount = 3
    static let kDismissPopButtonDelayTime: TimeInterval = 0.1
    
    // Event recording for sequence analysis
    private static var recordEvents: [NSEvent] = []
    private static var startPoint: CGPoint = CGPoint.zero
    private static var lastPoint: CGPoint = CGPoint.zero
    
    // Trigger state tracking
    private static var isMonitoring = false
    private static var delayedTextExtractionTimer: Timer?
    
    // Reference to main app delegate for callbacks
    private static weak var appDelegate: AppDelegate?
    
    // MARK: - Setup and Configuration
    
    static func setup(with delegate: AppDelegate) {
        appDelegate = delegate
        isMonitoring = true
        os_log("EasydictEventMonitor initialized", log: .lifecycle, type: .info)
    }
    
    static func cleanup() {
        isMonitoring = false
        cancelDelayedTextExtraction()
        recordEvents.removeAll()
        appDelegate = nil
        os_log("EasydictEventMonitor cleaned up", log: .lifecycle, type: .info)
    }
    
    // MARK: - Core Event Handling (Easydict's approach)
    
    static func handleLeftMouseDown(at point: CGPoint) {
        guard isMonitoring else { return }
        
        startPoint = point
        lastPoint = point
        
        os_log("Left mouse down at: (%.1f, %.1f)", log: .textSelection, type: .debug, point.x, point.y)
        
        // Cancel any pending text extraction
        cancelDelayedTextExtraction()
        
        // Clear previous event records
        recordEvents.removeAll()
        
        // Dismiss any existing popups if mouse is outside expanded area
        dismissPopupsIfNeeded(mouseLocation: point)
    }
    
    static func handleLeftMouseDragged(at point: CGPoint, event: NSEvent) {
        guard isMonitoring else { return }
        
        lastPoint = point
        
        // Record drag event for sequence analysis
        recordEvent(event)
        
        os_log("Left mouse dragged to: (%.1f, %.1f), recorded events: %d", 
               log: .textSelection, type: .debug, point.x, point.y, recordEvents.count)
    }
    
    static func handleLeftMouseUp(at point: CGPoint) {
        guard isMonitoring else { return }
        
        lastPoint = point
        
        os_log("Left mouse up at: (%.1f, %.1f)", log: .textSelection, type: .debug, point.x, point.y)
        
        // Easydict's core logic: Check if we have a consistent drag sequence
        if checkIfLeftMouseDragged() {
            os_log("Consistent drag sequence detected, scheduling delayed text extraction", 
                   log: .textSelection, type: .info)
            
            // Schedule delayed text extraction (Easydict's key strategy)
            scheduleDelayedTextExtraction()
        } else {
            os_log("No consistent drag sequence, checking for double-click compatibility", 
                   log: .textSelection, type: .debug)
            
            // For double-click compatibility: if no drag sequence but very small movement,
            // still allow delayed extraction (Easydict is more lenient)
            let distance = calculateTotalDragDistance()
            if distance < 10 {  // Small movement might still be text selection
                os_log("Small movement detected (%.1f px), allowing delayed extraction", 
                       log: .textSelection, type: .debug, distance)
                scheduleDelayedTextExtraction()
            }
        }
    }
    
    // MARK: - Event Sequence Analysis (Pure Easydict Logic)
    
    private static func recordEvent(_ event: NSEvent) {
        // Maintain only the last kRecordEventCount events
        if recordEvents.count >= kRecordEventCount {
            recordEvents.removeFirst()
        }
        recordEvents.append(event)
    }
    
    // Core Easydict method: Check if recorded events are all dragged events
    private static func checkIfLeftMouseDragged() -> Bool {
        // Need at least kRecordEventCount events
        guard recordEvents.count >= kRecordEventCount else {
            os_log("Not enough recorded events: %d < %d", log: .textSelection, type: .debug, 
                   recordEvents.count, kRecordEventCount)
            return false
        }
        
        // All events must be drag events
        for event in recordEvents {
            if event.type != .leftMouseDragged {
                os_log("Non-drag event found in sequence: %{public}@", log: .textSelection, type: .debug, 
                       String(describing: event.type))
                return false
            }
        }
        
        os_log("All %d recorded events are drag events - sequence valid", 
               log: .textSelection, type: .info, recordEvents.count)
        return true
    }
    
    // MARK: - Delayed Validation Strategy
    
    private static func scheduleDelayedTextExtraction() {
        // Cancel any existing timer
        cancelDelayedTextExtraction()
        
        // Use configured delay time
        let delayTime = EasydictConfiguration.getAdjustedDelayTime()
        
        // Schedule delayed execution - this is Easydict's key innovation
        delayedTextExtractionTimer = Timer.scheduledTimer(withTimeInterval: delayTime, repeats: false) { _ in
            performDelayedTextExtraction()
        }
        
        os_log("Scheduled delayed text extraction in %.3f seconds", 
               log: .textSelection, type: .info, delayTime)
    }
    
    private static func cancelDelayedTextExtraction() {
        delayedTextExtractionTimer?.invalidate()
        delayedTextExtractionTimer = nil
    }
    
    private static func performDelayedTextExtraction() {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("Performing delayed text extraction", log: .textSelection, type: .info)
        
        // At this point, we're confident it's a text selection gesture
        // No pre-filtering, no strict validation - just try to get text
        
        guard let delegate = appDelegate else {
            os_log("No app delegate available for text extraction", log: .textSelection, type: .error)
            EasydictConfiguration.recordDetectionAttempt(method: "easydict", success: false, duration: CFAbsoluteTimeGetCurrent() - startTime)
            return
        }
        
        // Create gesture data for compatibility with existing systems
        let _ = createGestureDataFromRecordedEvents()
        
        // Use the enhanced fallback system for text extraction
        if let text = delegate.getSelectedTextViaAccessibility(
            mouseUpLocation: lastPoint, 
            currentTime: CFAbsoluteTimeGetCurrent()
        ), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            os_log("Delayed text extraction successful: %{public}@ (%.3fs)", 
                   log: .textSelection, type: .info, String(text.prefix(50)), duration)
            
            // Record success statistics
            EasydictConfiguration.recordDetectionAttempt(method: "easydict", success: true, duration: duration)
            
            // Show popup immediately - no further validation needed
            delegate.showPopupMenu(for: text)
        } else {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            os_log("Delayed text extraction failed - no text found (%.3fs)", 
                   log: .textSelection, type: .info, duration)
            
            // Record failure statistics
            EasydictConfiguration.recordDetectionAttempt(method: "easydict", success: false, duration: duration)
        }
    }
    
    // MARK: - Popup Dismissal Logic (Easydict-style)
    
    private static func dismissPopupsIfNeeded(mouseLocation: CGPoint) {
        guard let delegate = appDelegate,
              let existingPopup = delegate.popupWindow,
              existingPopup.isVisible else {
            return
        }
        
        // Check if mouse is outside the expanded area around the popup
        let popupFrame = existingPopup.frame
        let expandedFrame = NSRect(
            x: popupFrame.origin.x - kExpandedRadiusValue,
            y: popupFrame.origin.y - kExpandedRadiusValue,
            width: popupFrame.width + kExpandedRadiusValue * 2,
            height: popupFrame.height + kExpandedRadiusValue * 2
        )
        
        if !expandedFrame.contains(mouseLocation) {
            os_log("Mouse outside expanded popup area, dismissing", log: .textSelection, type: .info)
            
            // Delay dismissal slightly to avoid flickering
            DispatchQueue.main.asyncAfter(deadline: .now() + kDismissPopButtonDelayTime) {
                delegate.hidePopupMenu()
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private static func createGestureDataFromRecordedEvents() -> GestureData {
        let distance = calculateTotalDragDistance()
        let duration = calculateTotalDragDuration()
        
        return GestureData(
            mouseDown: startPoint,
            mouseUp: lastPoint,
            duration: duration,
            distance: distance
        )
    }
    
    private static func calculateTotalDragDistance() -> Double {
        let deltaX = lastPoint.x - startPoint.x
        let deltaY = lastPoint.y - startPoint.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
    
    private static func calculateTotalDragDuration() -> TimeInterval {
        guard let firstEvent = recordEvents.first,
              let lastEvent = recordEvents.last else {
            return 0.0
        }
        return lastEvent.timestamp - firstEvent.timestamp
    }
    
    // MARK: - Advanced Popup Positioning (Easydict-style)
    
    static func calculateOptimalPopupPosition(for text: String, mouseLocation: CGPoint) -> CGPoint {
        // Easydict uses frame-based positioning with expanded radius consideration
        let frame = frameFromStartPoint(startPoint, endPoint: lastPoint)
        
        // Position popup near the selection but avoid screen edges
        var popupOrigin = CGPoint(
            x: frame.midX - 90, // Center horizontally around selection
            y: frame.maxY + 10  // Position below selection
        )
        
        // Adjust for screen boundaries
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let popupSize = NSSize(width: 180, height: 40)
            
            // Horizontal adjustment
            if popupOrigin.x + popupSize.width > screenFrame.maxX {
                popupOrigin.x = screenFrame.maxX - popupSize.width
            }
            if popupOrigin.x < screenFrame.minX {
                popupOrigin.x = screenFrame.minX
            }
            
            // Vertical adjustment - if no space below, position above
            if popupOrigin.y + popupSize.height > screenFrame.maxY {
                popupOrigin.y = frame.minY - popupSize.height - 10
            }
            if popupOrigin.y < screenFrame.minY {
                popupOrigin.y = screenFrame.minY
            }
        }
        
        return popupOrigin
    }
    
    // Easydict's frame calculation method
    private static func frameFromStartPoint(_ startPoint: CGPoint, endPoint: CGPoint) -> CGRect {
        let x = min(startPoint.x, endPoint.x)
        let y = min(startPoint.y, endPoint.y)
        
        var width = abs(startPoint.x - endPoint.x)
        var height = abs(startPoint.y - endPoint.y)
        
        // If width or height is 0, use expanded radius (Easydict's approach)
        if width == 0 {
            width = kExpandedRadiusValue * 2
        }
        if height == 0 {
            height = kExpandedRadiusValue * 2
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Integration Helpers
    
    static func shouldUseEasydictDetection() -> Bool {
        // Use configuration to determine if Easydict detection should be used
        return isMonitoring && EasydictConfiguration.shouldUseEasydictDetection()
    }
    
    static func getCurrentSelectionFrame() -> CGRect {
        return frameFromStartPoint(startPoint, endPoint: lastPoint)
    }
    
    static func getExpandedSelectionFrame() -> CGRect {
        let baseFrame = getCurrentSelectionFrame()
        return NSRect(
            x: baseFrame.origin.x - kExpandedRadiusValue,
            y: baseFrame.origin.y - kExpandedRadiusValue,
            width: baseFrame.width + kExpandedRadiusValue * 2,
            height: baseFrame.height + kExpandedRadiusValue * 2
        )
    }
}

// MARK: - Easydict Event Monitor Extension for Mouse Tracking

extension EasydictEventMonitor {
    
    // Check if point is inside expanded area (used for popup dismissal)
    static func isPoint(_ point: CGPoint, insideExpandedArea: Bool = true) -> Bool {
        let frame = insideExpandedArea ? getExpandedSelectionFrame() : getCurrentSelectionFrame()
        return frame.contains(point)
    }
    
    // Calculate distance between two points
    static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let deltaX = point2.x - point1.x
        let deltaY = point2.y - point1.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
    
    // Check if current gesture is likely a text selection based on Easydict criteria
    static func isLikelyTextSelection() -> Bool {
        // In Easydict's approach, if we have a drag sequence, it's likely text selection
        // The delayed validation will determine if text is actually available
        return checkIfLeftMouseDragged()
    }
}

// MARK: - Statistics and Debugging

extension EasydictEventMonitor {
    
    static func getDetectionStats() -> [String: Any] {
        return [
            "isMonitoring": isMonitoring,
            "recordedEvents": recordEvents.count,
            "startPoint": NSStringFromPoint(startPoint),
            "lastPoint": NSStringFromPoint(lastPoint),
            "hasDelayedTimer": delayedTextExtractionTimer != nil,
            "selectionFrame": NSStringFromRect(getCurrentSelectionFrame())
        ]
    }
    
    static func logCurrentState() {
        let stats = getDetectionStats()
        os_log("EasydictEventMonitor state: %{public}@", log: .textSelection, type: .debug, 
               String(describing: stats))
    }
}