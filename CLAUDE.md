# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run Commands

```bash
# Build the application
./build.sh

# Run the application
./SnapPop
```

The build process uses `swiftc` with Cocoa and Carbon frameworks. The resulting binary is a single executable file.

## Architecture Overview

SnapPop is a modular macOS application that mimics PopClip functionality by detecting text selection and showing a floating menu. The main application logic is in `main.swift` with specialized functionality organized in the `Sources/` directory.

### Core Components

**AppDelegate**: Main application controller that manages:
- Accessibility permissions checking (`checkAccessibilityPermissions()`)
- Status bar item setup (`setupStatusItem()`)
- Global mouse event monitoring (`setupTextSelectionMonitoring()`)
- Text selection detection logic

**PopupMenuWindow**: Custom NSWindow subclass that:
- Displays floating menu with Copy/Search buttons  
- Auto-positions near text selection with intelligent screen boundary detection
- Auto-closes after 1.5 seconds or on outside clicks/ESC key
- Features animated hover effects with random colors
- Pill-shaped design (40px height) with fade animations

**Modular Components** (Sources/ directory):
- **ApplicationSpecificHandler**: Handles app-specific text extraction methods for problematic applications
- **EnhancedEventValidator**: Sophisticated gesture classification to prevent false positives
- **PopupPositionCalculator**: Intelligent popup positioning based on selection direction and screen boundaries  
- **PopupDismissalManager**: Enhanced dismissal handling with multiple trigger methods
- **FallbackMethodController**: Manages fallback text extraction strategies
- **TextFrameValidator**: Validates text selection frames and boundaries

### Text Selection Detection Strategy

The application uses a multi-layered approach:

1. **Mouse Event Monitoring**: Captures both `leftMouseDown` and `leftMouseUp` events globally using Core Graphics event taps
2. **Enhanced Gesture Classification**: Sophisticated validation to prevent false triggers from:
   - Simple clicks vs. drag operations
   - Window resize operations
   - UI control interactions (buttons, scrollbars)
   - Double-click text selection detection
3. **Multi-Method Text Extraction**:
   - Primary: Accessibility API (`AXSelectedTextAttribute`, `AXSelectedTextRangeAttribute`)
   - Application-specific: Specialized handlers for problematic applications (Sublime Text, VS Code, browsers)
   - Fallback: CMD+C simulation with clipboard preservation
   - Hierarchical: Child element traversal for complex UI hierarchies

### Accessibility Requirements

The app requires "Accessibility" permissions to:
- Monitor global mouse events (`CGEvent.tapCreate`)
- Access selected text from other applications (`AXUIElement` APIs)
- The app automatically prompts users and can open System Preferences

### Key Implementation Details

- **Event Handling**: Uses Core Graphics event taps for global mouse monitoring with segfault prevention
- **Text Detection**: Multiple fallback methods ensure compatibility across different applications  
- **UI Design**: Follows macOS design guidelines with system color adaptation and dark mode support
- **Animation System**: Smooth fade-in/fade-out animations (150ms/100ms) with colorful hover effects
- **Memory Management**: Proper cleanup of event taps and timers to prevent leaks
- **Thread Safety**: Dispatch queue management for popup creation and dismissal

### Key Features

- **False Positive Prevention**: Sophisticated gesture validation prevents unwanted popup triggers
- **Multi-Application Support**: Specialized handling for text editors, browsers, and chat applications
- **Double-Click Support**: Enhanced detection for double-click text selection
- **Direction-Aware Positioning**: Intelligent popup placement based on selection direction
- **Comprehensive Logging**: Uses os.log for debugging and monitoring

## Development Rules

### Text Selection Detection Priority
1. **Always prioritize Accessibility APIs** - Use `AXUIElement` and related APIs as the primary method for text selection detection
2. **Avoid keyboard shortcuts/tricks** - Do not use CMD+C simulation or other keyboard event injection as solutions
3. **Exhaustive API exploration** - When accessibility methods fail, explore all available AX attributes and methods before considering alternatives
4. **Use context7.com for API research** - When working with macOS Accessibility APIs, consult https://context7.com for comprehensive documentation and usage patterns

### Accessibility API Best Practices
- Always check `AXIsProcessTrusted()` before attempting accessibility operations
- Use proper error handling for all `AXUIElementCopyAttributeValue` calls
- Traverse the accessibility hierarchy systematically (parent → children → siblings)
- Log all available attributes when debugging accessibility issues
- Test with multiple applications to ensure broad compatibility

## Development Notes

- Main application logic in `main.swift` with modular components in `Sources/` directory
- Uses only system frameworks (Cocoa, ApplicationServices, Carbon) - no external dependencies
- Requires macOS accessibility permissions to function properly
- Status bar integration allows easy application termination
- Build process creates single executable with `./build.sh`
- Comprehensive error handling and logging for debugging accessibility issues

## Debugging and Testing

- Use `Console.app` to view os.log output for debugging
- Test with multiple applications to ensure broad compatibility
- Verify accessibility permissions with System Preferences > Security & Privacy > Privacy > Accessibility
- Monitor popup positioning and dismissal behavior across different screen configurations