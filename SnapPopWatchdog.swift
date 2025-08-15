#!/usr/bin/env swift

import Foundation
import AppKit

// SnapPop Watchdog - 監控主進程並在crash時重啟
class SnapPopWatchdog {
    private let appBundlePath: String
    private let checkInterval: TimeInterval = 5.0
    private var monitoringTimer: Timer?
    private var lastRestartTime: Date = Date.distantPast
    private let minRestartInterval: TimeInterval = 10.0 // 防止快速重複重啟
    private let maxRestartAttempts = 5
    private var restartCount = 0
    
    init() {
        // 尋找SnapPop.app路徑
        if let appPath = findSnapPopApp() {
            self.appBundlePath = appPath
            print("Watchdog: Found SnapPop at \(appPath)")
        } else {
            // 默認路徑
            self.appBundlePath = "/Applications/SnapPop.app"
            print("Watchdog: Using default path \(appBundlePath)")
        }
    }
    
    private func findSnapPopApp() -> String? {
        let possiblePaths = [
            "/Applications/SnapPop.app",
            NSHomeDirectory() + "/Applications/SnapPop.app",
            Bundle.main.bundlePath.replacingOccurrences(of: "SnapPopWatchdog.app", with: "SnapPop.app"),
            FileManager.default.currentDirectoryPath + "/SnapPop.app"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    func startMonitoring() {
        print("Watchdog: Starting monitoring for SnapPop...")
        
        // 首次啟動SnapPop
        launchSnapPop()
        
        // 設置定期檢查
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkSnapPopStatus()
        }
        
        // 保持watchdog運行
        RunLoop.main.run()
    }
    
    private func checkSnapPopStatus() {
        let isRunning = isSnapPopRunning()
        
        if !isRunning {
            print("Watchdog: SnapPop not running, attempting restart...")
            
            // 檢查重啟間隔
            let timeSinceLastRestart = Date().timeIntervalSince(lastRestartTime)
            if timeSinceLastRestart < minRestartInterval {
                print("Watchdog: Too soon since last restart, waiting...")
                return
            }
            
            // 檢查重啟次數
            if restartCount >= maxRestartAttempts {
                print("Watchdog: Max restart attempts reached, stopping...")
                stopMonitoring()
                return
            }
            
            launchSnapPop()
            restartCount += 1
            lastRestartTime = Date()
        } else {
            // 重置重啟計數器
            restartCount = 0
        }
    }
    
    private func isSnapPopRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == "com.gradinnovate.snappop" ||
            app.localizedName == "SnapPop"
        }
    }
    
    private func launchSnapPop() {
        print("Watchdog: Launching SnapPop...")
        
        guard FileManager.default.fileExists(atPath: appBundlePath) else {
            print("Watchdog: ERROR - SnapPop.app not found at \(appBundlePath)")
            return
        }
        
        let url = URL(fileURLWithPath: appBundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // 不激活，保持背景運行
        
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error = error {
                print("Watchdog: ERROR launching SnapPop: \(error)")
            } else {
                print("Watchdog: SnapPop launched successfully")
            }
        }
    }
    
    func stopMonitoring() {
        print("Watchdog: Stopping monitoring...")
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}

// 主程序
print("SnapPop Watchdog starting...")

let watchdog = SnapPopWatchdog()

// 處理系統信號
signal(SIGTERM) { _ in
    print("Watchdog: Received SIGTERM, shutting down...")
    exit(0)
}

signal(SIGINT) { _ in
    print("Watchdog: Received SIGINT, shutting down...")
    exit(0)
}

// 開始監控
watchdog.startMonitoring()