import Cocoa
import os.log

// MARK: - Fallback Configuration for Settings
// This provides a simple UI to configure fallback strategy preferences

class FallbackConfigurationManager {
    
    enum FallbackPreference: String, CaseIterable {
        case menuBarFirst = "menuBarFirst"
        case cmdCFirst = "cmdCFirst"
        case automatic = "automatic"
        
        var displayName: String {
            switch self {
            case .menuBarFirst:
                return "Menu Bar Copy First"
            case .cmdCFirst:
                return "CMD+C First"
            case .automatic:
                return "Automatic (Smart Detection)"
            }
        }
        
        var description: String {
            switch self {
            case .menuBarFirst:
                return "Try menu bar copy action first, fallback to CMD+C if needed. Better for chat apps."
            case .cmdCFirst:
                return "Try CMD+C simulation first, fallback to menu bar if needed. Better for code editors."
            case .automatic:
                return "Automatically choose the best method based on the application type."
            }
        }
    }
    
    private static let preferenceKey = "SnapPopFallbackPreference"
    
    static var currentPreference: FallbackPreference {
        get {
            let stored = UserDefaults.standard.string(forKey: preferenceKey) ?? FallbackPreference.automatic.rawValue
            return FallbackPreference(rawValue: stored) ?? .automatic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
            os_log("Fallback preference changed to: %{public}@", log: .lifecycle, type: .info, newValue.displayName)
        }
    }
    
    // Application-specific overrides
    private static let appOverridesKey = "SnapPopAppFallbackOverrides"
    
    static func getPreferenceFor(application: String) -> FallbackPreference? {
        let overrides = UserDefaults.standard.dictionary(forKey: appOverridesKey) as? [String: String] ?? [:]
        guard let override = overrides[application.lowercased()],
              let preference = FallbackPreference(rawValue: override) else {
            return nil
        }
        return preference
    }
    
    static func setPreference(_ preference: FallbackPreference?, for application: String) {
        var overrides = UserDefaults.standard.dictionary(forKey: appOverridesKey) as? [String: String] ?? [:]
        
        if let preference = preference {
            overrides[application.lowercased()] = preference.rawValue
        } else {
            overrides.removeValue(forKey: application.lowercased())
        }
        
        UserDefaults.standard.set(overrides, forKey: appOverridesKey)
        os_log("App-specific fallback preference for %{public}@: %{public}@", 
               log: .lifecycle, type: .info, application, preference?.displayName ?? "Default")
    }
    
    // Statistics tracking for automatic optimization
    private static let statsKey = "SnapPopFallbackStats"
    
    static func recordSuccess(method: String, for application: String) {
        var stats = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: [String: Int]] ?? [:]
        
        let appKey = application.lowercased()
        if stats[appKey] == nil {
            stats[appKey] = [:]
        }
        
        let currentCount = stats[appKey]?[method] ?? 0
        stats[appKey]?[method] = currentCount + 1
        UserDefaults.standard.set(stats, forKey: statsKey)
    }
    
    static func recordFailure(method: String, for application: String) {
        recordSuccess(method: "\(method)_failure", for: application)
    }
    
    static func getSuccessRate(method: String, for application: String) -> Double {
        let stats = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: [String: Int]] ?? [:]
        let appStats = stats[application.lowercased()] ?? [:]
        
        let successes = appStats[method] ?? 0
        let failures = appStats["\(method)_failure"] ?? 0
        let total = successes + failures
        
        return total > 0 ? Double(successes) / Double(total) : 0.0
    }
    
    static func getBestMethod(for application: String) -> String? {
        let menuBarRate = getSuccessRate(method: "menuBar", for: application)
        let cmdCRate = getSuccessRate(method: "cmdC", for: application)
        
        // Need at least 3 attempts to make a recommendation
        let stats = UserDefaults.standard.dictionary(forKey: statsKey) as? [String: [String: Int]] ?? [:]
        let appStats = stats[application.lowercased()] ?? [:]
        
        let menuBarTotal = (appStats["menuBar"] ?? 0) + (appStats["menuBar_failure"] ?? 0)
        let cmdCTotal = (appStats["cmdC"] ?? 0) + (appStats["cmdC_failure"] ?? 0)
        
        if menuBarTotal >= 3 && cmdCTotal >= 3 {
            return menuBarRate > cmdCRate ? "menuBar" : "cmdC"
        }
        
        return nil // Not enough data
    }
}

// MARK: - Integration with EasydictFallbackController

extension EasydictFallbackController {
    
    static func getSelectedTextWithPreferences(
        for applicationName: String,
        element: AXUIElement,
        gestureData: GestureData? = nil
    ) -> String? {
        
        let preference = FallbackConfigurationManager.getPreferenceFor(application: applicationName) 
                        ?? FallbackConfigurationManager.currentPreference
        
        let strategy: FallbackStrategy
        
        switch preference {
        case .menuBarFirst:
            strategy = .menuBarActionFirst
            
        case .cmdCFirst:
            strategy = .simulatedShortcutFirst
            
        case .automatic:
            // Use statistical data to determine best method
            if let bestMethod = FallbackConfigurationManager.getBestMethod(for: applicationName) {
                strategy = bestMethod == "menuBar" ? .menuBarActionFirst : .simulatedShortcutFirst
                os_log("Using statistical best method for %{public}@: %{public}@", 
                       log: .textSelection, type: .info, applicationName, bestMethod)
            } else {
                // Fallback to original smart detection
                strategy = determineOptimalStrategy(for: applicationName)
            }
        }
        
        // Execute with tracking
        let startTime = CFAbsoluteTimeGetCurrent()
        var result: String?
        var usedMethod: String = ""
        
        switch strategy {
        case .simulatedShortcutFirst:
            result = getSelectedTextBySimulatedShortcutFirst(for: applicationName, element: element)
            usedMethod = result != nil ? "cmdC" : "cmdC_failure"
            
        case .menuBarActionFirst:
            result = getSelectedTextByMenuBarActionFirst(for: applicationName, element: element)
            usedMethod = result != nil ? "menuBar" : "menuBar_failure"
        }
        
        // Record statistics
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        if result != nil {
            FallbackConfigurationManager.recordSuccess(method: usedMethod.replacingOccurrences(of: "_failure", with: ""), 
                                                     for: applicationName)
            os_log("Fallback success: %{public}@ for %{public}@ (%.3fs)", 
                   log: .textSelection, type: .info, usedMethod, applicationName, duration)
        } else {
            FallbackConfigurationManager.recordFailure(method: usedMethod.replacingOccurrences(of: "_failure", with: ""), 
                                                      for: applicationName)
            os_log("Fallback failure: %{public}@ for %{public}@ (%.3fs)", 
                   log: .textSelection, type: .error, usedMethod, applicationName, duration)
        }
        
        return result
    }
}