import Cocoa
import ApplicationServices

// MARK: - Module 4: Enhanced Event Validator with Multi-layered Monitoring
class EnhancedEventValidator {
    // Event sequence tracking
    private static let kMaxEventHistory = 5
    private static var eventHistory: [EventRecord] = []
    private static var lastEventTime: CFTimeInterval = 0
    
    // Window operation detection
    private static var windowObserver: NSObjectProtocol?
    private static var workspaceObserver: NSObjectProtocol?
    private static var isWindowOperationInProgress = false
    private static var lastWindowOperationTime: CFTimeInterval = 0
    
    static func validateSelectionGesture(
        mouseDown: CGPoint,
        mouseUp: CGPoint,
        duration: CFTimeInterval,
        distance: Double
    ) -> ValidationResult {
        
        // Record this event in history for sequence analysis
        recordEvent(mouseDown: mouseDown, mouseUp: mouseUp, duration: duration, distance: distance)
        
        // Multi-layered validation approach like Easydict
        
        // Layer 1: Check for window operations in progress
        if isWindowOperationDetected() {
            return ValidationResult(isValid: false, reason: "Window operation detected - suppressing popup")
        }
        
        // Layer 2: Event sequence analysis
        if let sequenceResult = analyzeEventSequence() {
            if !sequenceResult.isValid {
                return sequenceResult
            }
        }
        
        // Layer 3: Drag operation classification
        let dragClassification = classifyDragOperation(mouseDown: mouseDown, mouseUp: mouseUp, distance: distance, duration: duration)
        if !dragClassification.isTextSelection {
            return ValidationResult(isValid: false, reason: dragClassification.reason)
        }
        
        // Layer 4: Basic gesture classification (preserved original logic)
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
    
    // Setup window and application monitoring
    static func setupWindowMonitoring() {
        // NSWindow notifications for resize/move detection
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { _ in
            markWindowOperationInProgress()
        }
        
        // NSWorkspace monitoring for application changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Reset event history when switching applications
            clearEventHistory()
        }
    }
    
    static func cleanup() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
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

// MARK: - Event Recording and Analysis Methods
extension EnhancedEventValidator {
    
    private static func recordEvent(mouseDown: CGPoint, mouseUp: CGPoint, duration: CFTimeInterval, distance: Double) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        let event = EventRecord(
            mouseDown: mouseDown,
            mouseUp: mouseUp,
            duration: duration,
            distance: distance,
            timestamp: currentTime,
            eventType: classifyEventType(distance: distance, duration: duration)
        )
        
        // Add to history and maintain size limit
        eventHistory.append(event)
        if eventHistory.count > kMaxEventHistory {
            eventHistory.removeFirst()
        }
        
        lastEventTime = currentTime
    }
    
    private static func classifyEventType(distance: Double, duration: CFTimeInterval) -> EventType {
        if distance > 100 && duration > 0.5 {
            return .longDrag
        } else if distance > 50 {
            return .drag
        } else if duration > 0.3 {
            return .longPress
        } else {
            return .click
        }
    }
    
    private static func analyzeEventSequence() -> ValidationResult? {
        guard eventHistory.count >= 2 else { return nil }
        
        let recentEvents = Array(eventHistory.suffix(3))
        
        // Check for rapid sequence of drag operations (potential window resize)
        let dragEvents = recentEvents.filter { $0.eventType == .drag || $0.eventType == .longDrag }
        if dragEvents.count >= 2 {
            let timeBetween = dragEvents.last!.timestamp - dragEvents.first!.timestamp
            if timeBetween < 2.0 { // Within 2 seconds
                return ValidationResult(isValid: false, reason: "Rapid drag sequence detected - likely window operation")
            }
        }
        
        // Check for pattern that indicates UI interactions
        if recentEvents.count >= 3 {
            let allClicks = recentEvents.allSatisfy { $0.eventType == .click }
            let allShortDistance = recentEvents.allSatisfy { $0.distance < 10 }
            
            if allClicks && allShortDistance {
                return ValidationResult(isValid: false, reason: "Multiple clicks detected - likely UI interaction")
            }
        }
        
        return nil // No issues found in sequence
    }
    
    private static func classifyDragOperation(mouseDown: CGPoint, mouseUp: CGPoint, distance: Double, duration: CFTimeInterval) -> DragClassification {
        // Classify based on movement pattern and context
        
        let deltaX = abs(mouseUp.x - mouseDown.x)
        let deltaY = abs(mouseUp.y - mouseDown.y)
        
        // Window resize detection - starts near screen edges
        guard let screen = NSScreen.main else {
            return DragClassification(isTextSelection: true, reason: "Cannot determine screen bounds")
        }
        
        let screenFrame = screen.visibleFrame
        let edgeThreshold: CGFloat = 30
        
        let nearEdge = mouseDown.x < screenFrame.minX + edgeThreshold ||
                      mouseDown.x > screenFrame.maxX - edgeThreshold ||
                      mouseDown.y < screenFrame.minY + edgeThreshold ||
                      mouseDown.y > screenFrame.maxY - edgeThreshold
        
        if nearEdge && distance > 50 {
            return DragClassification(isTextSelection: false, reason: "Edge drag detected - likely window resize")
        }
        
        // File move detection - large diagonal movements
        let isDiagonal = min(deltaX, deltaY) > max(deltaX, deltaY) * 0.3
        if isDiagonal && distance > 200 {
            return DragClassification(isTextSelection: false, reason: "Large diagonal drag - likely file/window move")
        }
        
        // Text selection typically has high aspect ratio (more linear)
        let aspectRatio = max(deltaX, deltaY) / max(min(deltaX, deltaY), 1)
        if aspectRatio < 1.5 && distance > 100 {
            return DragClassification(isTextSelection: false, reason: "Square drag pattern - likely UI interaction")
        }
        
        return DragClassification(isTextSelection: true, reason: "Pattern consistent with text selection")
    }
    
    private static func isWindowOperationDetected() -> Bool {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Check if window operation was recent (within 500ms)
        if isWindowOperationInProgress && (currentTime - lastWindowOperationTime) < 0.5 {
            return true
        }
        
        // Reset flag if enough time has passed
        if (currentTime - lastWindowOperationTime) > 1.0 {
            isWindowOperationInProgress = false
        }
        
        return false
    }
    
    private static func markWindowOperationInProgress() {
        isWindowOperationInProgress = true
        lastWindowOperationTime = CFAbsoluteTimeGetCurrent()
    }
    
    private static func clearEventHistory() {
        eventHistory.removeAll()
    }
}

// MARK: - Supporting Types
struct EventRecord {
    let mouseDown: CGPoint
    let mouseUp: CGPoint
    let duration: CFTimeInterval
    let distance: Double
    let timestamp: CFTimeInterval
    let eventType: EventType
}

enum EventType {
    case click
    case longPress
    case drag
    case longDrag
}

struct DragClassification {
    let isTextSelection: Bool
    let reason: String
}

struct ValidationResult {
    let isValid: Bool
    let reason: String
}