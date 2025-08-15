# SnapPop Distribution Guide

這份文檔說明如何發布SnapPop到Homebrew和其他分發渠道。

## 📦 發布流程

### 1. 準備發布

```bash
# 確保所有更改已提交
git add .
git commit -m "Prepare for release v1.2.0"
git push origin main

# 創建並推送標籤
git tag v1.2.0
git push origin v1.2.0
```

### 2. 自動構建和發布

推送標籤後，GitHub Actions會自動：
- 構建應用程式
- 創建ZIP檔案
- 計算SHA256
- 創建GitHub Release
- 上傳二進制文件

### 3. 手動構建（可選）

```bash
# 使用發布腳本
./release.sh

# 上傳生成的ZIP到GitHub Releases
```

## 🍺 Homebrew發布

### 方法1：官方homebrew-cask（推薦）

1. **Fork homebrew-cask倉庫**：
   ```bash
   # 在GitHub上fork https://github.com/Homebrew/homebrew-cask
   git clone https://github.com/YOUR_USERNAME/homebrew-cask.git
   cd homebrew-cask
   ```

2. **創建cask文件**：
   ```bash
   cp /path/to/snappop/snappop.rb Casks/s/snappop.rb
   # 編輯文件，更新URL和SHA256
   ```

3. **測試cask**：
   ```bash
   brew install --cask ./Casks/s/snappop.rb
   brew uninstall --cask snappop
   ```

4. **提交PR**：
   ```bash
   git checkout -b add-snappop
   git add Casks/s/snappop.rb
   git commit -m "Add SnapPop v1.2.0"
   git push origin add-snappop
   # 在GitHub創建PR到Homebrew/homebrew-cask
   ```

### 方法2：自定義tap

1. **創建homebrew-tap倉庫**：
   ```bash
   # 在GitHub創建 homebrew-snappop 倉庫
   git clone https://github.com/YOUR_USERNAME/homebrew-snappop.git
   cd homebrew-snappop
   ```

2. **添加cask**：
   ```bash
   mkdir -p Casks
   cp /path/to/snappop/snappop.rb Casks/snappop.rb
   git add .
   git commit -m "Add SnapPop cask"
   git push origin main
   ```

3. **用戶安裝方式**：
   ```bash
   brew tap YOUR_USERNAME/snappop
   brew install --cask snappop
   ```

## 🔧 更新Homebrew Cask

### 自動更新流程

1. **獲取新版本信息**：
   ```bash
   # 從GitHub Release獲取
   VERSION="1.2.0"
   URL="https://github.com/YOUR_USERNAME/snappop/releases/download/v${VERSION}/SnapPop-${VERSION}.zip"
   SHA256=$(curl -sL "$URL" | shasum -a 256 | cut -d ' ' -f 1)
   ```

2. **更新cask文件**：
   ```ruby
   # 更新 snappop.rb
   version "1.2.0"
   sha256 "新的SHA256值"
   ```

3. **提交更新**：
   ```bash
   git add Casks/s/snappop.rb
   git commit -m "Update SnapPop to v1.2.0"
   git push origin main
   ```

### 自動化腳本

```bash
#!/bin/bash
# update-homebrew.sh

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

# 下載並計算SHA256
URL="https://github.com/YOUR_USERNAME/snappop/releases/download/v${VERSION}/SnapPop-${VERSION}.zip"
curl -sL "$URL" -o temp.zip
SHA256=$(shasum -a 256 temp.zip | cut -d ' ' -f 1)
rm temp.zip

# 更新cask文件
sed -i '' "s/version \".*\"/version \"$VERSION\"/" snappop.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" snappop.rb

echo "Updated to version $VERSION"
echo "SHA256: $SHA256"
```

## 📋 發布檢查清單

### 發布前
- [ ] 所有功能測試通過
- [ ] 更新版本號
- [ ] 更新CHANGELOG
- [ ] 測試構建腳本
- [ ] 測試應用程式功能

### 發布時
- [ ] 創建GitHub Release
- [ ] 上傳二進制文件
- [ ] 更新Homebrew cask
- [ ] 測試Homebrew安裝

### 發布後
- [ ] 驗證下載連結
- [ ] 測試用戶安裝流程
- [ ] 更新文檔
- [ ] 宣布新版本

## 🔍 故障排除

### 常見問題

1. **SHA256不匹配**：
   ```bash
   # 重新計算SHA256
   shasum -a 256 SnapPop-1.2.0.zip
   ```

2. **Homebrew審核失敗**：
   - 檢查cask語法
   - 確保URL可訪問
   - 驗證應用程式簽名

3. **自動構建失敗**：
   - 檢查GitHub Actions日誌
   - 驗證構建環境
   - 檢查權限設置

### 測試命令

```bash
# 測試本地cask
brew install --cask ./snappop.rb

# 檢查cask語法
brew cask audit snappop

# 測試完整安裝流程
brew uninstall --cask snappop
brew install --cask snappop
```

## 📊 發布統計

可以通過以下方式追蹤發布統計：

1. **GitHub Releases下載量**
2. **Homebrew安裝統計**（如果被接受到官方cask）
3. **用戶反饋和問題報告**

## 🚀 未來改進

- 自動化版本號更新
- 集成代碼簽名
- 多平台構建支持
- 更詳細的安裝後配置