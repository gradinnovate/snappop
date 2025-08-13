import Foundation

// MARK: - Module 6: Fallback Method Controller
class FallbackMethodController {
    
    struct GestureData {
        let mouseDown: CGPoint
        let mouseUp: CGPoint
        let duration: TimeInterval
        let distance: Double
    }
    
    static func shouldUseCmdCFallback(for appName: String, gestureData: GestureData?) -> Bool {
        let normalizedAppName = appName.lowercased()
        
        // Chrome-specific restrictions
        if normalizedAppName.contains("chrome") {
            return shouldUseCmdCForChrome(gestureData: gestureData)
        }
        
        // Safari-specific restrictions
        if normalizedAppName.contains("safari") {
            return shouldUseCmdCForSafari(gestureData: gestureData)
        }
        
        // Firefox-specific restrictions
        if normalizedAppName.contains("firefox") {
            return shouldUseCmdCForFirefox(gestureData: gestureData)
        }
        
        // Default: allow CMD+C for other applications
        return true
    }
    
    private static func shouldUseCmdCForChrome(gestureData: GestureData?) -> Bool {
        print("Chrome detected - evaluating CMD+C fallback necessity")
        
        guard let gesture = gestureData else {
            print("Chrome: No gesture data available - rejecting CMD+C")
            return false
        }
        
        // Chrome requires clear text selection gestures
        let hasSignificantDrag = gesture.distance >= 10
        let hasLongHold = gesture.duration >= 0.5
        
        if !hasSignificantDrag && !hasLongHold {
            print("Chrome: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Chrome: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
    
    private static func shouldUseCmdCForSafari(gestureData: GestureData?) -> Bool {
        print("Safari detected - evaluating CMD+C fallback necessity")
        
        guard let gesture = gestureData else {
            print("Safari: No gesture data available - rejecting CMD+C")
            return false
        }
        
        // Safari is slightly more lenient than Chrome
        let hasMinimalDrag = gesture.distance >= 5
        let hasMinimalHold = gesture.duration >= 0.3
        
        if !hasMinimalDrag && !hasMinimalHold {
            print("Safari: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Safari: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
    
    private static func shouldUseCmdCForFirefox(gestureData: GestureData?) -> Bool {
        print("Firefox detected - evaluating CMD+C fallback necessity")
        
        // Firefox generally has better accessibility support, be more restrictive
        guard let gesture = gestureData else {
            print("Firefox: No gesture data available - rejecting CMD+C")
            return false
        }
        
        let hasSignificantDrag = gesture.distance >= 15
        let hasLongHold = gesture.duration >= 0.6
        
        if !hasSignificantDrag && !hasLongHold {
            print("Firefox: Insufficient gesture evidence (distance: \(gesture.distance)px, time: \(gesture.duration)s) - rejecting CMD+C")
            return false
        }
        
        print("Firefox: Justified CMD+C usage - distance: \(gesture.distance)px, duration: \(gesture.duration)s")
        return true
    }
}