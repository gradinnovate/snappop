# SnapPop - Enhanced Text Selection Tool

SnapPop是一個macOS實用工具，模仿PopClip功能，通過檢測文本選擇並顯示浮動菜單來進行復制和搜索等快速操作。

## 新功能 ✨

### 🌟 背景應用程式
- SnapPop現在作為背景應用運行（無dock圖標）
- 靜默啟動，不打擾工作流程
- 通過狀態欄菜單訪問

### 🔄 崩潰自動重啟
- 使用launchd的內置崩潰恢復系統
- 應用程式崩潰時自動重啟
- 可配置的重啟限制，防止快速循環

### ⏸️ 監控控制
- **暫停/恢復**：臨時禁用文本選擇監控
- 狀態欄圖標變化指示暫停狀態
- 通過狀態欄菜單快速切換

### 🚀 登錄時啟動
- 選項：登錄時自動啟動SnapPop
- 通過狀態欄菜單輕鬆切換
- 使用macOS launch agents實現可靠啟動

### 🔒 增強權限處理
- 清晰的accessibility權限授予說明
- 缺少權限時的多個選項：
  - 直接打開系統偏好設置
  - 以有限功能繼續
  - 退出應用程式
- 自動權限監控和成功反饋
- 缺少權限時狀態欄警告

## 安裝

### 自動安裝
```bash
./install.sh
```

### 手動安裝
1. 構建應用程式：
   ```bash
   ./build.sh
   ```
2. 將 `SnapPop.app` 複製到 `/Applications/`
3. 從應用程式文件夾啟動

## 使用方法

### 首次啟動
1. 從應用程式啟動SnapPop
2. 如果提示，授予accessibility權限：
   - 點擊"打開系統偏好設置"
   - 如需要解鎖設置
   - 找到"SnapPop"並啟用它
   - 權限將自動檢測

### 狀態欄菜單
點擊狀態欄中的SnapPop圖標訪問：
- **狀態**：顯示監控是否活動或暫停
- **暫停/恢復監控**：切換文本選擇檢測
- **登錄時啟動**：啟用/禁用自動啟動
- **授予Accessibility權限**：如缺少權限則請求
- **檢測設置**：查看和配置檢測模式
- **關於**：應用程式信息
- **退出**：退出應用程式

### 文本選擇
1. 在任何應用程式中拖動選擇文本
2. 彈出菜單將出現在選擇附近
3. 從可用操作中選擇：
   - **複製**：複製文本到剪貼板
   - **搜索**：在Google搜索文本

## 檢測模式

SnapPop支持多種檢測策略：

### Easydict模式（默認）
- 純事件序列檢測
- 最響應和寬鬆
- 延遲驗證策略

### 混合模式
- 結合Easydict檢測與驗證
- 準確性和響應性之間的平衡方法

### 傳統模式
- 基於距離和時間閾值
- 最保守，較少誤報

### 自適應模式
- 根據應用程式自動選擇最佳方法
- 基於應用兼容性的智能檢測

## 配置

### 命令行設置
```bash
# 更改檢測模式
defaults write com.gradinnovate.snappop SnapPopDetectionMode "easydict"

# 調整靈敏度（0.1到3.0）
defaults write com.gradinnovate.snappop SnapPopSensitivity 1.5

# 啟用調試模式
defaults write com.gradinnovate.snappop SnapPopDebugMode -bool true
```

### 自動重啟配置
對於系統級崩潰保護，安裝launch daemon：
```bash
sudo cp com.gradinnovate.snappop.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.gradinnovate.snappop.plist
```

## 故障排除

### 權限問題
- 確保SnapPop在系統偏好設置 > 安全性與隱私 > 隱私 > 輔助功能中列出
- 嘗試從輔助功能列表中移除並重新添加SnapPop
- 授予權限後重啟SnapPop

### 性能問題
- 在檢測設置中調整靈敏度
- 切換到傳統模式以減少誤報
- 檢查Console.app中的SnapPop日誌

### 監控不工作
- 檢查監控是否暫停（狀態欄圖標顯示暫停符號）
- 驗證已授予accessibility權限
- 重啟應用程式

## 卸載

```bash
./uninstall.sh
```

這將移除：
- /Applications中的應用程式
- Launch agents和daemons
- 用戶偏好設置
- 日誌文件

## 系統要求

- macOS 10.15或更高版本
- Accessibility權限
- 可選：系統級崩潰保護需要管理員權限

## 許可證

Copyright © 2025 Grad Innovate. 保留所有權利。

---

如需支持或有問題，請檢查Console.app中的"SnapPop"條目。
EOF < /dev/null