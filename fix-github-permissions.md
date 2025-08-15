# 修復GitHub Actions權限問題

## 🔧 解決步驟

### 1. 檢查倉庫設置

在您的GitHub倉庫中：

1. **前往Settings（設置）**
   - 點擊倉庫頁面頂部的"Settings"標籤

2. **檢查Actions權限**
   - 左側菜單：Actions → General
   - 確保選擇：**"Allow all actions and reusable workflows"**
   - 向下滾動到"Workflow permissions"部分

3. **設置Workflow權限**
   - 選擇：**"Read and write permissions"**
   - 勾選：**"Allow GitHub Actions to create and approve pull requests"**
   - 點擊"Save"

### 2. 使用新的Workflow

我已經創建了一個更可靠的workflow文件：
- `.github/workflows/release-simple.yml`

您可以：
1. 刪除舊的`release.yml`文件
2. 使用新的`release-simple.yml`
3. 或者兩個都保留進行測試

### 3. 重新運行Release

```bash
# 刪除舊的標籤和release（如果需要）
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# 重新創建標籤
git tag v1.2.0
git push origin v1.2.0
```

### 4. 手動觸發（如果需要）

1. 前往GitHub → Actions
2. 選擇"Simple Release"工作流程
3. 點擊"Run workflow"
4. 輸入版本號：1.2.0
5. 點擊"Run workflow"

### 5. 驗證權限設置

檢查以下位置的設置：

#### 倉庫級別設置
- Settings → Actions → General
  - Actions permissions: "Allow all actions"
  - Workflow permissions: "Read and write permissions"

#### 組織級別設置（如果適用）
- 如果倉庫在組織下，檢查組織的Actions設置
- Organization Settings → Actions → General

### 6. 常見問題排查

#### 問題1: Token權限不足
**解決方案**: 在倉庫設置中啟用"Read and write permissions"

#### 問題2: 分支保護規則
**解決方案**: 檢查main分支的保護規則，確保Actions可以創建releases

#### 問題3: 組織限制
**解決方案**: 如果倉庫在組織下，檢查組織的Actions策略

### 7. 測試新的Workflow

```bash
# 使用簡化的發布腳本
./quick-release.sh 1.2.1 "測試新的workflow"
```

### 8. 成功指標

✅ 工作流程顯示綠色（成功）
✅ GitHub Releases頁面有新版本
✅ ZIP文件可以下載
✅ SHA256正確計算

### 9. 如果仍然失敗

1. **檢查Actions日誌**：
   - GitHub → Actions → 選擇失敗的工作流程
   - 查看詳細錯誤信息

2. **使用GitHub CLI（可選）**：
   ```bash
   # 安裝GitHub CLI
   brew install gh
   
   # 手動創建release
   gh release create v1.2.0 SnapPop-1.2.0.zip --title "SnapPop v1.2.0" --notes "Release notes here"
   ```

3. **聯繫支持**：
   - 如果問題持續，可能是GitHub的臨時問題
   - 檢查GitHub Status頁面

## 🎯 推薦的工作流程選擇

使用 **`release-simple.yml`** 因為：
- ✅ 使用最新的action版本
- ✅ 更簡潔的配置
- ✅ 明確的權限設置
- ✅ 更好的錯誤處理