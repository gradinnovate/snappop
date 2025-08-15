#!/bin/bash

# Check GitHub Actions Release Status
# 檢查發布狀態的實用腳本

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}📊 $1${NC}"
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

echo -e "${BLUE}"
echo "🔍 SnapPop 發布狀態檢查"
echo "========================"
echo -e "${NC}"

# 檢查Git標籤
print_status "檢查最新標籤..."
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "無標籤")
echo "最新標籤: $LATEST_TAG"

if [ "$LATEST_TAG" != "無標籤" ]; then
    # 檢查標籤是否已推送到遠程
    if git ls-remote --tags origin | grep -q "refs/tags/$LATEST_TAG"; then
        print_success "標籤 $LATEST_TAG 已推送到GitHub"
    else
        print_warning "標籤 $LATEST_TAG 尚未推送到GitHub"
    fi
    
    # 檢查本地構建
    if [ -f "SnapPop-${LATEST_TAG#v}.zip" ]; then
        print_success "本地發布檔案存在: SnapPop-${LATEST_TAG#v}.zip"
        echo "檔案大小: $(ls -lh SnapPop-${LATEST_TAG#v}.zip | awk '{print $5}')"
        echo "SHA256: $(shasum -a 256 SnapPop-${LATEST_TAG#v}.zip | cut -d ' ' -f 1)"
    else
        print_warning "本地發布檔案不存在"
        echo "執行 ./release.sh 來創建本地構建"
    fi
else
    print_error "沒有找到Git標籤"
    echo "使用 git tag v1.2.0 && git push origin v1.2.0 來創建發布"
fi

echo ""

# 檢查GitHub狀態
print_status "GitHub倉庫狀態..."

# 檢查遠程URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "未設置")
if [[ $REMOTE_URL == *"github.com"* ]]; then
    print_success "GitHub遠程倉庫已配置: $REMOTE_URL"
    
    # 提取用戶名和倉庫名
    if [[ $REMOTE_URL =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        USERNAME=${BASH_REMATCH[1]}
        REPO=${BASH_REMATCH[2]}
        echo "用戶名: $USERNAME"
        echo "倉庫名: $REPO"
        
        echo ""
        echo "🔗 有用的連結:"
        echo "• GitHub Actions: https://github.com/$USERNAME/$REPO/actions"
        echo "• GitHub Releases: https://github.com/$USERNAME/$REPO/releases"
        echo "• 最新發布: https://github.com/$USERNAME/$REPO/releases/latest"
    fi
else
    print_error "GitHub遠程倉庫未正確配置: $REMOTE_URL"
fi

echo ""

# 檢查工作流程文件
print_status "檢查工作流程配置..."
if [ -f ".github/workflows/release.yml" ]; then
    print_success "GitHub Actions工作流程文件存在"
else
    print_error "GitHub Actions工作流程文件不存在"
    echo "請確保 .github/workflows/release.yml 文件存在並已推送"
fi

# 檢查必要文件
print_status "檢查必要文件..."
REQUIRED_FILES=("build.sh" "Info.plist" "main.swift")
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "$file 存在"
    else
        print_error "$file 不存在"
    fi
done

echo ""

# 提供操作建議
echo -e "${YELLOW}📋 下一步操作建議:${NC}"

if [ "$LATEST_TAG" == "無標籤" ]; then
    echo "1. 創建發布標籤:"
    echo "   ./quick-release.sh 1.2.0 \"版本描述\""
elif ! git ls-remote --tags origin | grep -q "refs/tags/$LATEST_TAG"; then
    echo "1. 推送標籤到GitHub:"
    echo "   git push origin $LATEST_TAG"
else
    echo "1. 檢查GitHub Actions狀態"
    echo "2. 等待構建完成"
    echo "3. 檢查GitHub Releases頁面"
    echo "4. 更新Homebrew Cask"
fi

echo ""
echo -e "${GREEN}🎯 快速命令:${NC}"
echo "• 創建發布: ./quick-release.sh <版本號>"
echo "• 本地構建: ./release.sh"
echo "• 檢查狀態: ./check-release.sh"
echo "• 打開Actions: open 'https://github.com/$USERNAME/$REPO/actions'"
echo "• 打開Releases: open 'https://github.com/$USERNAME/$REPO/releases'"