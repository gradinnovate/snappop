import Cocoa
import os.log

// MARK: - Easydict Detection Configuration
// Provides runtime configuration for detection behavior

class EasydictConfiguration {
    
    // Detection mode selection
    enum DetectionMode: String, CaseIterable {
        case easydictOnly = "easydict"           // Pure Easydict approach
        case hybridSmartDetection = "hybrid"     // Easydict + SnapPop validation
        case traditionalOnly = "traditional"    // Original SnapPop approach
        case adaptive = "adaptive"              // Auto-select based on context
        
        var displayName: String {
            switch self {
            case .easydictOnly:
                return "Easydict (Pure Event Sequence)"
            case .hybridSmartDetection:
                return "Hybrid (Easydict + Validation)"
            case .traditionalOnly:
                return "Traditional (Distance + Time)"
            case .adaptive:
                return "Adaptive (Auto-Select Best)"
            }
        }
        
        var description: String {
            switch self {
            case .easydictOnly:
                return "Uses pure event sequence detection with delayed validation. Most responsive."
            case .hybridSmartDetection:
                return "Combines Easydict detection with light validation. Balanced approach."
            case .traditionalOnly:
                return "Original SnapPop approach with distance/time thresholds. Most conservative."
            case .adaptive:
                return "Automatically selects the best detection method based on application and context."
            }
        }
    }
    
    // Configuration storage
    private static let detectionModeKey = "SnapPopDetectionMode"
    private static let sensitivityKey = "SnapPopSensitivity"
    private static let delayTimeKey = "SnapPopDelayTime"
    private static let debugModeKey = "SnapPopDebugMode"
    
    // Current configuration
    static var detectionMode: DetectionMode {
        get {
            let stored = UserDefaults.standard.string(forKey: detectionModeKey) ?? DetectionMode.easydictOnly.rawValue
            return DetectionMode(rawValue: stored) ?? .easydictOnly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: detectionModeKey)
            os_log("Detection mode changed to: %{public}@", log: .lifecycle, type: .info, newValue.displayName)
        }
    }
    
    // Sensitivity multiplier for detection thresholds
    static var sensitivity: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: sensitivityKey)
            return stored > 0 ? stored : 1.0  // Default to normal sensitivity
        }
        set {
            UserDefaults.standard.set(max(0.1, min(3.0, newValue)), forKey: sensitivityKey)
            os_log("Sensitivity changed to: %.2f", log: .lifecycle, type: .info, newValue)
        }
    }
    
    // Custom delay time for text extraction
    static var delayTime: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: delayTimeKey)
            return stored > 0 ? stored : EasydictEventMonitor.kDelayGetSelectedTextTime
        }
        set {
            UserDefaults.standard.set(max(0.01, min(1.0, newValue)), forKey: delayTimeKey)
            os_log("Delay time changed to: %.3f", log: .lifecycle, type: .info, newValue)
        }
    }
    
    // Debug mode for detailed logging
    static var debugMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: debugModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: debugModeKey)
            os_log("Debug mode: %{public}@", log: .lifecycle, type: .info, newValue ? "enabled" : "disabled")
        }
    }
    
    // MARK: - Detection Logic Selection
    
    static func shouldUseEasydictDetection(for applicationName: String = "") -> Bool {
        switch detectionMode {
        case .easydictOnly:
            return true
            
        case .traditionalOnly:
            return false
            
        case .hybridSmartDetection:
            return true  // Use Easydict with validation
            
        case .adaptive:
            return getAdaptiveDecision(for: applicationName)
        }
    }
    
    static func shouldSkipValidation() -> Bool {
        return detectionMode == .easydictOnly
    }
    
    // MARK: - Adaptive Logic
    
    private static func getAdaptiveDecision(for applicationName: String) -> Bool {
        let appNameLower = applicationName.lowercased()
        
        // Applications that work better with Easydict approach
        let easydictFavoredApps = [
            "wechat", "telegram", "slack", "discord", "whatsapp",
            "messages", "mail", "notes", "textedit", "pages",
            "word", "excel", "powerpoint", "keynote"
        ]
        
        // Applications that might need more careful validation
        let traditionalFavoredApps = [
            "finder", "terminal", "xcode", "activity monitor",
            "system preferences", "calculator", "preview"
        ]
        
        for app in easydictFavoredApps {
            if appNameLower.contains(app) {
                return true
            }
        }
        
        for app in traditionalFavoredApps {
            if appNameLower.contains(app) {
                return false
            }
        }
        
        // Default to Easydict for unknown apps
        return true
    }
    
    // MARK: - Dynamic Threshold Calculation
    
    static func getAdjustedDistanceThreshold() -> Double {
        let baseThreshold = detectionMode == .easydictOnly ? 0.0 : 1.0
        return baseThreshold / sensitivity
    }
    
    static func getAdjustedTimeThreshold() -> TimeInterval {
        let baseThreshold = detectionMode == .easydictOnly ? 0.0 : 0.1
        return baseThreshold / sensitivity
    }
    
    static func getAdjustedDelayTime() -> TimeInterval {
        return delayTime * (2.0 - sensitivity)  // Lower sensitivity = longer delay
    }
    
    // MARK: - Statistics and Performance Tracking
    
    private static let statsKey = "SnapPopDetectionStats"
    
    static func recordDetectionAttempt(method: String, success: Bool, duration: TimeInterval) {
        guard var stats = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: [String: Any]] else {
            let newStats = [method: [
                "attempts": 1,
                "successes": success ? 1 : 0,
                "totalDuration": duration,
                "averageDuration": duration
            ]]
            UserDefaults.standard.set(newStats, forKey: statsKey)
            return
        }
        
        var methodStats = stats[method] ?? [:]
        let attempts = (methodStats["attempts"] as? Int ?? 0) + 1
        let successes = (methodStats["successes"] as? Int ?? 0) + (success ? 1 : 0)
        let totalDuration = (methodStats["totalDuration"] as? TimeInterval ?? 0.0) + duration
        
        methodStats["attempts"] = attempts
        methodStats["successes"] = successes
        methodStats["totalDuration"] = totalDuration
        methodStats["averageDuration"] = totalDuration / Double(attempts)
        methodStats["successRate"] = Double(successes) / Double(attempts)
        
        stats[method] = methodStats
        UserDefaults.standard.set(stats, forKey: statsKey)
        
        if debugMode {
            os_log("Detection stats - %{public}@: %d attempts, %.1f%% success, %.3fs avg", 
                   log: .textSelection, type: .debug, method, attempts, 
                   (Double(successes) / Double(attempts)) * 100, totalDuration / Double(attempts))
        }
    }
    
    static func getDetectionStats() -> [String: [String: Any]] {
        return UserDefaults.standard.dictionary(forKey: statsKey) as? [String: [String: Any]] ?? [:]
    }
    
    static func resetStats() {
        UserDefaults.standard.removeObject(forKey: statsKey)
        os_log("Detection statistics reset", log: .lifecycle, type: .info)
    }
    
    // MARK: - Debug Utilities
    
    static func logCurrentConfiguration() {
        let config: [String: Any] = [
            "detectionMode": detectionMode.displayName,
            "sensitivity": sensitivity,
            "delayTime": delayTime,
            "debugMode": debugMode,
            "distanceThreshold": getAdjustedDistanceThreshold(),
            "timeThreshold": getAdjustedTimeThreshold(),
            "adjustedDelay": getAdjustedDelayTime()
        ]
        
        os_log("Current configuration: %{public}@", log: .lifecycle, type: .info, 
               String(describing: config))
    }
    
    static func exportConfiguration() -> [String: Any] {
        return [
            "detectionMode": detectionMode.rawValue,
            "sensitivity": sensitivity,
            "delayTime": delayTime,
            "debugMode": debugMode,
            "stats": getDetectionStats()
        ]
    }
    
    static func importConfiguration(_ config: [String: Any]) {
        if let mode = config["detectionMode"] as? String,
           let detectionMode = DetectionMode(rawValue: mode) {
            self.detectionMode = detectionMode
        }
        
        if let sensitivity = config["sensitivity"] as? Double {
            self.sensitivity = sensitivity
        }
        
        if let delay = config["delayTime"] as? TimeInterval {
            self.delayTime = delay
        }
        
        if let debug = config["debugMode"] as? Bool {
            self.debugMode = debug
        }
        
        os_log("Configuration imported successfully", log: .lifecycle, type: .info)
    }
}

// MARK: - Configuration Change Notification

extension Notification.Name {
    static let easydictConfigurationChanged = Notification.Name("EasydictConfigurationChanged")
}

extension EasydictConfiguration {
    
    static func notifyConfigurationChanged() {
        NotificationCenter.default.post(name: .easydictConfigurationChanged, object: nil)
    }
    
    static func observeConfigurationChanges(using block: @escaping () -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: .easydictConfigurationChanged,
            object: nil,
            queue: .main
        ) { _ in
            block()
        }
    }
}