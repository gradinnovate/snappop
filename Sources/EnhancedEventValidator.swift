import Cocoa

// MARK: - Module 4: Enhanced Event Validator
class EnhancedEventValidator {
    
    static func validateSelectionGesture(
        mouseDown: CGPoint,
        mouseUp: CGPoint,
        duration: CFTimeInterval,
        distance: Double
    ) -> ValidationResult {
        
        // Basic gesture classification
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

struct ValidationResult {
    let isValid: Bool
    let reason: String
}