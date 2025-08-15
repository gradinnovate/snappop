# GitHub Actions Release 工作流程指南

## 🚀 如何觸發自動發布

### 方法1：標籤觸發（推薦）

1. **確保代碼已推送**：
```bash
git add .
git commit -m "Prepare for release v1.2.0"
git push origin main
```

2. **創建並推送標籤**：
```bash
# 創建標籤
git tag v1.2.0

# 推送標籤到GitHub（這將觸發工作流程）
git push origin v1.2.0
```

3. **查看工作流程**：
   - 前往 GitHub倉庫 → Actions標籤
   - 您將看到"Release"工作流程正在運行

### 方法2：手動觸發

1. **前往GitHub Actions**：
   - 打開您的GitHub倉庫
   - 點擊"Actions"標籤
   - 選擇"Release"工作流程

2. **手動運行**：
   - 點擊"Run workflow"按鈕
   - 選擇分支（通常是main）
   - 輸入版本號（例如：1.2.0）
   - 點擊"Run workflow"

## 📋 工作流程步驟解析

### 步驟1：環境設置
```yaml
- uses: actions/checkout@v4          # 檢出代碼
- uses: maxim-lobanov/setup-xcode@v1 # 設置Xcode環境
```

### 步驟2：版本提取
```yaml
- name: Get version
  # 從標籤或手動輸入獲取版本號
```

### 步驟3：構建應用程式
```yaml
- name: Build SnapPop
  run: |
    ./build.sh  # 運行您的構建腳本
    # 更新Info.plist中的版本
```

### 步驟4：創建發布檔案
```yaml
- name: Create ZIP archive
  # 打包應用程式並計算SHA256
```

### 步驟5：創建GitHub Release
```yaml
- name: Create Release
  # 創建GitHub Release頁面
  # 包含版本說明和下載連結
```

### 步驟6：上傳檔案
```yaml
- name: Upload Release Asset
  # 上傳ZIP檔案到Release
```

## 🔧 首次設置

### 1. 確保GitHub倉庫已設置
```bash
# 如果還沒有倉庫
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/snappop.git
git push -u origin main
```

### 2. 驗證工作流程文件
確保`.github/workflows/release.yml`存在並已推送到倉庫。

### 3. 設置權限（如果需要）
在GitHub倉庫設置中：
- Settings → Actions → General
- 確保"Allow GitHub Actions to create and approve pull requests"已啟用

## 🎯 實際操作示例

### 場景：發布v1.2.0版本

1. **準備代碼**：
```bash
# 確保所有更改已提交
git status
git add .
git commit -m "Fix start at login duplicate instance issue"
git push origin main
```

2. **創建發布**：
```bash
# 創建標籤（這將觸發GitHub Actions）
git tag v1.2.0
git push origin v1.2.0
```

3. **監控進度**：
   - 前往 https://github.com/YOUR_USERNAME/snappop/actions
   - 查看"Release"工作流程狀態
   - 預期運行時間：2-5分鐘

4. **檢查結果**：
   - 前往 https://github.com/YOUR_USERNAME/snappop/releases
   - 應該看到新的v1.2.0發布
   - 包含SnapPop-1.2.0.zip下載連結

## 🔍 故障排除

### 常見問題

#### 1. 工作流程沒有觸發
**原因**：標籤沒有正確推送
```bash
# 檢查標籤是否存在
git tag -l

# 重新推送標籤
git push origin v1.2.0 --force
```

#### 2. 構建失敗
**原因**：build.sh腳本在GitHub環境中失敗
```bash
# 檢查build.sh是否有執行權限
chmod +x build.sh
git add build.sh
git commit -m "Fix build script permissions"
git push origin main
```

#### 3. 權限錯誤
**檢查**：
- GitHub Token權限
- 倉庫Actions設置
- 分支保護規則

### 調試方法

1. **查看Actions日誌**：
   - GitHub → Actions → 選擇失敗的工作流程
   - 點擊查看詳細日誌

2. **本地測試**：
```bash
# 在本地測試構建腳本
./build.sh

# 檢查生成的文件
ls -la SnapPop.app
```

## 📊 工作流程監控

### 成功指標
- ✅ 工作流程狀態顯示綠色
- ✅ GitHub Release已創建
- ✅ ZIP檔案可下載
- ✅ SHA256已計算

### 失敗處理
如果工作流程失敗：
1. 查看詳細錯誤日誌
2. 修復問題
3. 刪除失敗的標籤和發布
4. 重新創建標籤

```bash
# 刪除失敗的標籤
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# 修復問題後重新創建
git tag v1.2.0
git push origin v1.2.0
```

## 🎉 成功後的步驟

發布成功後：

1. **驗證下載**：
   - 測試ZIP檔案下載
   - 驗證應用程式運行

2. **更新Homebrew**：
   - 複製新的SHA256值
   - 更新snappop.rb文件
   - 提交到homebrew-cask

3. **通知用戶**：
   - 在README中更新版本號
   - 發布更新公告

## 🔄 自動化改進

### 未來可添加的功能：

1. **自動更新Homebrew Cask**
2. **多平台構建**
3. **代碼簽名**
4. **自動化測試**
5. **發布通知**

### 示例改進的工作流程：
```yaml
# 可以添加更多步驟
- name: Run tests
  run: ./test.sh

- name: Sign application
  run: codesign --sign "Developer ID" SnapPop.app

- name: Notarize application
  run: xcrun notarytool submit SnapPop.zip
```