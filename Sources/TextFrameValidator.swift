import Cocoa
import ApplicationServices
import os.log

// MARK: - Module 1: Text Frame Validator
class TextFrameValidator {
    static func validateMousePositionInTextFrame(_ element: AXUIElement, mouseDownLocation: CGPoint?, currentMouseLocation: CGPoint?) -> Bool {
        guard let mouseDown = mouseDownLocation, let currentMouse = currentMouseLocation else {
            os_log("Missing mouse position data, skipping validation", log: .validation, type: .info)
            return true // Fallback to original behavior if no mouse data
        }
        
        // Try to get the text selection frame
        guard let textFrame = getTextSelectionFrame(from: element) else {
            print("TextFrameValidator: Could not get text frame, allowing selection")
            return true // Fallback to original behavior if frame unavailable
        }
        
        // Expand frame by 40px (like Easydict) to handle imprecise bounds
        let expandedFrame = textFrame.insetBy(dx: -40, dy: -40)
        
        let mouseDownInFrame = expandedFrame.contains(mouseDown)
        let currentMouseInFrame = expandedFrame.contains(currentMouse)
        
        print("TextFrameValidator: Frame=\(textFrame), Expanded=\(expandedFrame)")
        print("TextFrameValidator: MouseDown(\(mouseDown)) in frame: \(mouseDownInFrame)")
        print("TextFrameValidator: CurrentMouse(\(currentMouse)) in frame: \(currentMouseInFrame)")
        
        // Both start and end positions should be within the text area
        return mouseDownInFrame && currentMouseInFrame
    }
    
    static func getTextSelectionFrame(from element: AXUIElement) -> CGRect? {
        // Method 1: Try to get bounds for selected text range
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
           let range = selectedRange {
            
            var textFrame: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range,
                &textFrame
            )
            
            if result == .success, let frame = textFrame {
                if CFGetTypeID(frame) == AXValueGetTypeID() {
                    let axValue = frame as! AXValue
                    var rect = CGRect.zero
                    if AXValueGetValue(axValue, .cgRect, &rect) {
                        debugPrint("TextFrameValidator: Got text frame via bounds for range: \(rect)")
                        return rect
                    }
                }
            }
        }
        
        // Method 2: Fallback to element's general frame  
        var elementFrame: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &elementFrame) == .success,
           let frame = elementFrame {
            if CFGetTypeID(frame) == AXValueGetTypeID() {
                let axValue = frame as! AXValue
                var size = CGSize.zero
                if AXValueGetValue(axValue, .cgSize, &size) {
                    // Try to get position as well
                    var positionRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
                       let posRef = positionRef, CFGetTypeID(posRef) == AXValueGetTypeID() {
                        let posValue = posRef as! AXValue
                        var position = CGPoint.zero
                        if AXValueGetValue(posValue, .cgPoint, &position) {
                            let rect = CGRect(origin: position, size: size)
                            debugPrint("TextFrameValidator: Got element frame as fallback: \(rect)")
                            return rect
                        }
                    }
                }
            }
        }
        
        os_log("Could not get any frame information", log: .validation, type: .debug)
        return nil
    }
}