import Cocoa

// MARK: - Module 2: Popup Position Calculator
class PopupPositionCalculator {
    static func calculateSmartPosition(
        originalPosition: NSPoint,
        mouseLocation: CGPoint,
        mouseDownLocation: CGPoint?,
        windowSize: NSSize,
        selectedText: String
    ) -> NSPoint {
        
        // Detect text selection direction if we have mouse down data
        let selectionDirection = detectSelectionDirection(
            mouseDown: mouseDownLocation,
            mouseUp: mouseLocation
        )
        
        // Calculate enhanced position based on selection direction
        var smartPosition = calculateDirectionalPosition(
            mouseLocation: mouseLocation,
            direction: selectionDirection,
            windowSize: windowSize
        )
        
        // Apply screen boundary handling with safety margins (like Easydict)
        smartPosition = applySafetyConstraints(
            position: smartPosition,
            windowSize: windowSize,
            safetyMargin: 50
        )
        
        print("PopupPositionCalculator: Original=\(originalPosition), Smart=\(smartPosition), Direction=\(selectionDirection)")
        
        // Return smart position if valid, otherwise fallback to original
        return isValidPosition(smartPosition, windowSize: windowSize) ? smartPosition : originalPosition
    }
    
    private static func detectSelectionDirection(mouseDown: CGPoint?, mouseUp: CGPoint) -> SelectionDirection {
        guard let mouseDown = mouseDown else {
            return .unknown
        }
        
        let deltaX = mouseUp.x - mouseDown.x
        let deltaY = mouseUp.y - mouseDown.y
        
        // Determine primary direction based on larger movement
        if abs(deltaX) > abs(deltaY) {
            return deltaX > 0 ? .leftToRight : .rightToLeft
        } else {
            return deltaY > 0 ? .topToBottom : .bottomToTop
        }
    }
    
    private static func calculateDirectionalPosition(
        mouseLocation: CGPoint,
        direction: SelectionDirection,
        windowSize: NSSize
    ) -> NSPoint {
        
        let offset: CGFloat = 20 // Distance from selection
        
        switch direction {
        case .leftToRight:
            // Position to the right of selection end
            return NSPoint(x: mouseLocation.x + offset, y: mouseLocation.y - windowSize.height - offset)
            
        case .rightToLeft:
            // Position to the left of selection end
            return NSPoint(x: mouseLocation.x - windowSize.width - offset, y: mouseLocation.y - windowSize.height - offset)
            
        case .topToBottom:
            // Position below selection end
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y - windowSize.height - offset)
            
        case .bottomToTop:
            // Position above selection end
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y + offset)
            
        case .unknown:
            // Fallback to centered position slightly below
            return NSPoint(x: mouseLocation.x - windowSize.width/2, y: mouseLocation.y - windowSize.height - offset)
        }
    }
    
    private static func applySafetyConstraints(
        position: NSPoint,
        windowSize: NSSize,
        safetyMargin: CGFloat
    ) -> NSPoint {
        
        guard let screen = NSScreen.main else {
            return position
        }
        
        let screenFrame = screen.visibleFrame
        let safeFrame = screenFrame.insetBy(dx: safetyMargin, dy: safetyMargin)
        
        var safePosition = position
        
        // Horizontal constraints
        safePosition.x = max(safeFrame.minX, min(safePosition.x, safeFrame.maxX - windowSize.width))
        
        // Vertical constraints  
        safePosition.y = max(safeFrame.minY, min(safePosition.y, safeFrame.maxY - windowSize.height))
        
        return safePosition
    }
    
    private static func isValidPosition(_ position: NSPoint, windowSize: NSSize) -> Bool {
        guard let screen = NSScreen.main else {
            return false
        }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = NSRect(origin: position, size: windowSize)
        
        return screenFrame.contains(windowFrame)
    }
}

enum SelectionDirection {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
    case unknown
}