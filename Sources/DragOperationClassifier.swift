import Cocoa
import ApplicationServices
import os.log

// MARK: - Advanced Drag Operation Classifier
class DragOperationClassifier {
    
    // Classification thresholds based on Easydict patterns
    private static let textSelectionMaxDistance: Double = 600
    private static let windowResizeMinDistance: Double = 30
    private static let fileMoveMinDistance: Double = 100
    private static let uiInteractionMaxDistance: Double = 20
    
    // Pattern analysis constants  
    private static let linearityThreshold: Double = 2.5  // Aspect ratio for linear movement
    private static let edgeThreshold: CGFloat = 50       // Distance from screen edge
    
    static func classifyDragOperation(_ gestureData: GestureData) -> DragOperationResult {
        
        let mouseDown = gestureData.mouseDown
        let mouseUp = gestureData.mouseUp
        let distance = gestureData.distance
        let duration = gestureData.duration
        
        // Calculate movement characteristics
        let deltaX = abs(mouseUp.x - mouseDown.x)
        let deltaY = abs(mouseUp.y - mouseDown.y)
        let aspectRatio = max(deltaX, deltaY) / max(min(deltaX, deltaY), 1)
        
        os_log("Drag analysis: distance=%.1f, duration=%.3f, aspectRatio=%.1f", 
               log: .validation, type: .debug, distance, duration, aspectRatio)
        
        // Layer 1: Immediate disqualification patterns
        
        // Very small movements - likely UI clicks
        if distance < 3 {
            return DragOperationResult(
                classification: .uiInteraction,
                confidence: 0.95,
                reason: "Movement too small (%.1f px) - likely click",
                isTextSelectionCandidate: false
            )
        }
        
        // Very large, fast movements - likely window/file operations  
        if distance > 800 && duration < 0.5 {
            return DragOperationResult(
                classification: .windowOperation,
                confidence: 0.90,
                reason: "Large fast movement - likely window operation",
                isTextSelectionCandidate: false
            )
        }
        
        // Layer 2: Context-based classification
        
        // Window resize detection (starts near edges)
        if let windowResizeResult = detectWindowResize(mouseDown: mouseDown, distance: distance, aspectRatio: aspectRatio) {
            return windowResizeResult
        }
        
        // File move detection (large diagonal movements)
        if let fileMoveResult = detectFileMove(distance: distance, duration: duration, aspectRatio: aspectRatio, deltaX: deltaX, deltaY: deltaY) {
            return fileMoveResult
        }
        
        // Layer 3: Text selection validation
        
        // Highly linear movements - strong text selection candidate
        if aspectRatio > 5.0 && distance > 10 {
            let confidence = min(0.95, 0.7 + (aspectRatio - 5.0) * 0.05)
            return DragOperationResult(
                classification: .textSelection,
                confidence: confidence,
                reason: "Highly linear movement (ratio: %.1f) - strong text selection",
                isTextSelectionCandidate: true
            )
        }
        
        // Moderately linear movements
        if aspectRatio > linearityThreshold {
            let confidence = 0.6 + min(0.3, (aspectRatio - linearityThreshold) * 0.1)
            return DragOperationResult(
                classification: .textSelection,
                confidence: confidence,
                reason: "Linear movement pattern - likely text selection",
                isTextSelectionCandidate: true
            )
        }
        
        // Layer 4: Duration-based analysis
        
        // Slow, careful movements - might be text selection
        if duration > 0.8 && distance < 300 {
            return DragOperationResult(
                classification: .textSelection,
                confidence: 0.65,
                reason: "Slow, careful movement - possible text selection",
                isTextSelectionCandidate: true
            )
        }
        
        // Quick movements with moderate distance
        if duration < 0.2 && distance > 50 && distance < 200 {
            return DragOperationResult(
                classification: .uiInteraction,
                confidence: 0.75,
                reason: "Quick moderate movement - likely UI interaction",
                isTextSelectionCandidate: false
            )
        }
        
        // Layer 5: Default classification based on distance
        
        if distance > textSelectionMaxDistance {
            return DragOperationResult(
                classification: .windowOperation,
                confidence: 0.70,
                reason: "Distance exceeds text selection threshold",
                isTextSelectionCandidate: false
            )
        }
        
        if distance < uiInteractionMaxDistance {
            return DragOperationResult(
                classification: .uiInteraction,
                confidence: 0.80,
                reason: "Short distance movement - likely UI interaction",
                isTextSelectionCandidate: false
            )
        }
        
        // Default: Allow with moderate confidence
        return DragOperationResult(
            classification: .textSelection,
            confidence: 0.50,
            reason: "Pattern unclear - allowing with caution",
            isTextSelectionCandidate: true
        )
    }
    
    // MARK: - Specialized Detection Methods
    
    private static func detectWindowResize(mouseDown: CGPoint, distance: Double, aspectRatio: Double) -> DragOperationResult? {
        guard let screen = NSScreen.main else { return nil }
        
        let screenFrame = screen.visibleFrame
        
        // Check if drag started near screen edges
        let nearLeftEdge = mouseDown.x < screenFrame.minX + edgeThreshold
        let nearRightEdge = mouseDown.x > screenFrame.maxX - edgeThreshold  
        let nearTopEdge = mouseDown.y > screenFrame.maxY - edgeThreshold
        let nearBottomEdge = mouseDown.y < screenFrame.minY + edgeThreshold
        
        let nearScreenEdge = nearLeftEdge || nearRightEdge || nearTopEdge || nearBottomEdge
        
        if nearScreenEdge && distance > windowResizeMinDistance {
            let confidence = min(0.90, 0.7 + (distance / 100) * 0.1)
            
            var edgeDescription = "screen edge"
            if nearLeftEdge { edgeDescription = "left edge" }
            else if nearRightEdge { edgeDescription = "right edge" }
            else if nearTopEdge { edgeDescription = "top edge" }
            else if nearBottomEdge { edgeDescription = "bottom edge" }
            
            return DragOperationResult(
                classification: .windowResize,
                confidence: confidence,
                reason: "Drag from \(edgeDescription) - likely window resize",
                isTextSelectionCandidate: false
            )
        }
        
        return nil
    }
    
    private static func detectFileMove(distance: Double, duration: CFTimeInterval, aspectRatio: Double, deltaX: CGFloat, deltaY: CGFloat) -> DragOperationResult? {
        
        // File moves typically have these characteristics:
        // 1. Moderate to long distance
        // 2. Diagonal movement (not highly linear)
        // 3. Reasonable duration (not too fast, not too slow)
        
        let isModerateDistance = distance > fileMoveMinDistance && distance < 800
        let isDiagonal = aspectRatio < 3.0 && min(deltaX, deltaY) > 20
        let isReasonableDuration = duration > 0.1 && duration < 4.0
        
        if isModerateDistance && isDiagonal && isReasonableDuration {
            // Higher confidence for longer distances with good diagonal movement
            let distanceFactor = min(1.0, distance / 300)  
            let diagonalFactor = (3.0 - aspectRatio) / 3.0  // Lower aspect ratio = more diagonal
            let confidence = 0.6 + (distanceFactor * diagonalFactor * 0.3)
            
            return DragOperationResult(
                classification: .fileMove,
                confidence: confidence,
                reason: "Diagonal movement pattern - likely file move/drag",
                isTextSelectionCandidate: false
            )
        }
        
        // Very long diagonal drags are almost certainly file operations
        if distance > 400 && isDiagonal {
            return DragOperationResult(
                classification: .fileMove,
                confidence: 0.85,
                reason: "Long diagonal drag - strong file move indication",
                isTextSelectionCandidate: false
            )
        }
        
        return nil
    }
    
    // MARK: - Utility Methods
    
    static func isTextSelectionLikely(_ result: DragOperationResult) -> Bool {
        return result.isTextSelectionCandidate && result.confidence > 0.5
    }
    
    static func shouldSuppressPopup(_ result: DragOperationResult) -> Bool {
        // Suppress if it's definitely not text selection or confidence is too low
        return !result.isTextSelectionCandidate || 
               (result.classification != .textSelection && result.confidence > 0.7)
    }
}

// MARK: - Supporting Types

enum DragOperationType {
    case textSelection
    case windowResize
    case windowMove
    case windowOperation  // Generic window operation
    case fileMove
    case uiInteraction    // Button clicks, slider drags, etc.
    case unknown
}

struct DragOperationResult {
    let classification: DragOperationType
    let confidence: Double  // 0.0 to 1.0
    let reason: String
    let isTextSelectionCandidate: Bool
    
    init(classification: DragOperationType, confidence: Double, reason: String, isTextSelectionCandidate: Bool) {
        self.classification = classification
        self.confidence = max(0.0, min(1.0, confidence))  // Clamp to valid range
        self.reason = String(format: reason, arguments: [])  // Format string safely
        self.isTextSelectionCandidate = isTextSelectionCandidate
    }
}