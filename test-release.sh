#!/bin/bash

# Test GitHub Actions Release
# 測試GitHub Actions發布功能

set -e

VERSION="1.2.1"
echo "🧪 測試GitHub Actions Release v$VERSION"
echo "======================================="

# 檢查當前狀態
echo "📊 當前狀態:"
echo "• Git分支: $(git branch --show-current)"
echo "• 最新標籤: $(git describe --tags --abbrev=0 2>/dev/null || echo '無')"
echo "• 未提交更改: $(git status --porcelain | wc -l | tr -d ' ') 個文件"

echo ""

# 檢查必要文件
echo "🔍 檢查必要文件:"
FILES=(".github/workflows/release-simple.yml" "build.sh" "Info.plist")
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file 不存在"
        exit 1
    fi
done

echo ""

# 提交更改
if [ -n "$(git status --porcelain)" ]; then
    echo "📝 提交未保存的更改..."
    git add .
    git commit -m "Fix GitHub Actions permissions and add simplified workflow"
    git push origin main
    echo "✅ 更改已提交並推送"
else
    echo "✅ 沒有待提交的更改"
fi

echo ""

# 刪除舊標籤（如果存在）
if git tag -l | grep -q "^v$VERSION$"; then
    echo "🗑️  刪除現有標籤 v$VERSION..."
    git tag -d "v$VERSION"
    git push origin ":refs/tags/v$VERSION" 2>/dev/null || true
    echo "✅ 舊標籤已刪除"
fi

echo ""

# 創建新標籤
echo "🏷️  創建測試標籤 v$VERSION..."
git tag -a "v$VERSION" -m "Test release v$VERSION - GitHub Actions permissions fix"
git push origin "v$VERSION"
echo "✅ 標籤已推送，GitHub Actions應該已觸發"

echo ""
echo "🎯 下一步:"
echo "1. 前往GitHub Actions查看進度:"
echo "   https://github.com/YOUR_USERNAME/snappop/actions"
echo ""
echo "2. 檢查Simple Release工作流程狀態"
echo ""
echo "3. 如果成功，檢查GitHub Releases:"
echo "   https://github.com/YOUR_USERNAME/snappop/releases"
echo ""
echo "4. 預期結果:"
echo "   - SnapPop-$VERSION.zip 文件"
echo "   - 完整的發布說明"
echo "   - 正確的SHA256校驗和"

# 可選：打開瀏覽器
read -p "是否在瀏覽器中打開GitHub Actions? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://github.com/YOUR_USERNAME/snappop/actions"
    fi
fi

echo ""
echo "✨ 測試發布已啟動！等待GitHub Actions完成..."