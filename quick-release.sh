#!/bin/bash

# SnapPop Quick Release Script
# 自動化版本發布流程

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函數定義
print_step() {
    echo -e "${BLUE}🔹 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 檢查參數
if [ -z "$1" ]; then
    echo "用法: $0 <版本號> [說明]"
    echo "示例: $0 1.2.0 \"修復重複實例問題\""
    exit 1
fi

VERSION=$1
DESCRIPTION=${2:-"SnapPop v$VERSION 發布"}

echo -e "${BLUE}"
echo "🚀 SnapPop 快速發布工具"
echo "=============================="
echo -e "${NC}"
echo "版本: $VERSION"
echo "說明: $DESCRIPTION"
echo ""

# 1. 檢查Git狀態
print_step "檢查Git狀態..."
if ! git diff-index --quiet HEAD --; then
    print_warning "有未提交的更改"
    echo "未提交的文件:"
    git status --porcelain
    echo ""
    read -p "是否繼續? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "發布已取消"
        exit 1
    fi
fi

# 2. 檢查是否在main分支
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    print_warning "當前分支不是main: $CURRENT_BRANCH"
    read -p "是否切換到main分支? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout main
        git pull origin main
    fi
fi

# 3. 提交所有更改
if ! git diff-index --quiet HEAD --; then
    print_step "提交所有更改..."
    git add .
    git commit -m "Prepare for release v$VERSION: $DESCRIPTION"
    print_success "更改已提交"
fi

# 4. 推送到遠程
print_step "推送到遠程倉庫..."
git push origin main
print_success "代碼已推送"

# 5. 檢查標籤是否已存在
if git tag -l | grep -q "^v$VERSION$"; then
    print_warning "標籤 v$VERSION 已存在"
    read -p "是否刪除並重新創建? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "v$VERSION"
        git push origin ":refs/tags/v$VERSION"
        print_success "舊標籤已刪除"
    else
        print_error "發布已取消"
        exit 1
    fi
fi

# 6. 創建標籤
print_step "創建發布標籤 v$VERSION..."
git tag -a "v$VERSION" -m "Release v$VERSION: $DESCRIPTION"
print_success "標籤已創建"

# 7. 推送標籤（觸發GitHub Actions）
print_step "推送標籤到GitHub（將觸發自動構建）..."
git push origin "v$VERSION"
print_success "標籤已推送"

echo ""
echo -e "${GREEN}🎉 發布流程啟動成功！${NC}"
echo ""
echo "📋 接下來的步驟:"
echo "1. 前往 GitHub Actions 查看構建進度"
echo "   https://github.com/YOUR_USERNAME/snappop/actions"
echo ""
echo "2. 構建完成後檢查 GitHub Releases"
echo "   https://github.com/YOUR_USERNAME/snappop/releases"
echo ""
echo "3. 預期文件:"
echo "   - SnapPop-$VERSION.zip"
echo "   - 自動生成的發布說明"
echo "   - SHA256校驗和"
echo ""
echo "4. 更新Homebrew Cask (構建完成後):"
echo "   - 複製新的SHA256值"
echo "   - 更新 snappop.rb 文件"
echo "   - 提交到 homebrew-cask"
echo ""

# 8. 可選：打開瀏覽器查看進度
read -p "是否在瀏覽器中打開GitHub Actions頁面? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 檢測操作系統並打開瀏覽器
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://github.com/YOUR_USERNAME/snappop/actions"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "https://github.com/YOUR_USERNAME/snappop/actions"
    else
        echo "請手動打開: https://github.com/YOUR_USERNAME/snappop/actions"
    fi
fi

echo ""
print_success "快速發布腳本執行完成！"