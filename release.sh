#!/bin/bash

# ==========================================
# 自动打包并双分支发布脚本 (Git Bash / Linux)
# ==========================================

# 确保脚本中任何命令出错时立即停止执行
set -e

# 1. 获取并确保在 master 目标分支启动
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "master")
if [ -z "$CURRENT_BRANCH" ]; then
    CURRENT_BRANCH="master"
fi

if [ "$CURRENT_BRANCH" != "master" ]; then
    echo "⚠️ 警告：当前不在 master 开发分支，正在自动切换回 master 分支..."
    git checkout master
fi

# 2. 获取要发布的版本号
read -p "请输入要发布的版本号 (例如 v1.0.0, 默认 v1.0.0): " VERSION
if [ -z "$VERSION" ]; then
    VERSION="v1.0.0"
fi

echo -e "\n========== [步骤 1] 开始在 master 分支本地打包 =========="
pyinstaller --onefile --noconsole --name="全景下载合成工具" gui.py

if [ $? -ne 0 ]; then
    echo "❌ PyInstaller 打包失败，请检查编译环境或依赖！"
    exit 1
fi
echo "✨ 本地打包成功，生成文件：dist/全景下载合成工具.exe"

# 3. 自动关联 GitHub 远程仓库
GITHUB_REMOTE_URL="git@github.com:Mjrooo/720yundownload.git"
if ! git remote | grep -q "^github$"; then
    echo "正在自动关联 GitHub 远程仓库: $GITHUB_REMOTE_URL"
    git remote add github "$GITHUB_REMOTE_URL"
fi

# 4. 在 master 分支提交所有内容 (包含所有源码与开发配置的备份)
echo -e "\n========== [步骤 2] 在 master 开发分支提交所有源码与配置 =========="
git add .
if git diff-index --quiet HEAD --; then
    echo "master 分支源码无新更改需要提交。"
else
    git commit -m "Dev update & build for $VERSION"
fi

# 提示是否推送 master 分支（包含源码）到远程
# 注意：如果您的 GitHub 仓库是公开的，请选 n（否），只把源码留在本地，只推送无源码的 main 分支！
read -p "是否同步推送 master 源码开发分支到所有 Git 远程仓库？(y/n, 默认 n): " PUSH_MASTER
if [ "$PUSH_MASTER" = "y" ] || [ "$PUSH_MASTER" = "Y" ]; then
    REMOTES=$(git remote)
    for R in $REMOTES; do
        echo "正在推送 master 分支到远程仓库: $R ..."
        git push "$R" master
    done
else
    echo "已跳过推送 master 远程源码分支，源码仅在本地进行 commit 留存。"
fi

# 5. 切换到 main 分支发布打包文件
echo -e "\n========== [步骤 3] 切换到 main 分支仅发布打包与公开文件 =========="
# 备份打包成果 EXE 和公共必要配置到临时目录
TEMP_DIR=$(mktemp -d)
cp dist/全景下载合成工具.exe "$TEMP_DIR/"
[ -f README.md ] && cp README.md "$TEMP_DIR/"
[ -f requirements.txt ] && cp requirements.txt "$TEMP_DIR/"
[ -f release.sh ] && cp release.sh "$TEMP_DIR/"

# 检查 main 分支是否存在，不存在则创建
if ! git show-ref --verify --quiet refs/heads/main; then
    echo "创建并初始化 main 分支..."
    git checkout --orphan main
else
    git checkout main
fi

# 清空 main 分支下所有的文件（确保不带任何源码，只带公开文件和编译成果）
git rm -rf . --ignore-unmatch 2>/dev/null || true
rm -rf *

# 恢复备份的发布文件到 main 分支
mkdir -p dist
cp "$TEMP_DIR/全景下载合成工具.exe" dist/
[ -f "$TEMP_DIR/README.md" ] && cp "$TEMP_DIR/README.md" .
[ -f "$TEMP_DIR/requirements.txt" ] && cp "$TEMP_DIR/requirements.txt" .
[ -f "$TEMP_DIR/release.sh" ] && cp "$TEMP_DIR/release.sh" .

# 创建 main 分支专用的 .gitignore（对 main 分支而言，过滤 build 临时文件夹即可）
cat <<EOF > .gitignore
build/
__pycache__/
*.pyc
*.pyo
*.pyd
*.so
.auth_cache.json
EOF

# 清理临时目录
rm -rf "$TEMP_DIR"

# 在 main 分支上提交并强制推送到所有关联的远程仓库
git add .
git commit -m "Release version $VERSION (Distribution files only)"

REMOTES=$(git remote)
for R in $REMOTES; do
    echo "正在推送 main 分支到远程仓库: $R ..."
    git push "$R" main --force
done

# 清除已存在的本地和远程 Tag 冲突
git tag -d "$VERSION" 2>/dev/null || true
for R in $REMOTES; do
    git push "$R" --delete "$VERSION" 2>/dev/null || true
done

git tag "$VERSION"
for R in $REMOTES; do
    echo "正在推送 Tag [$VERSION] 到远程仓库: $R ..."
    git push "$R" "$VERSION"
done

# 6. 检查 GitHub CLI (gh) 自动发布
if ! command -v gh &> /dev/null; then
    echo -e "\n=========================================================="
    echo "⚠️ 注意：本地尚未安装 GitHub CLI (gh) 命令行工具！"
    echo "请前往安装: https://cli.github.com/ 并在终端运行 \`gh auth login\` 登录。"
    echo "=========================================================="
    echo "程序已为您推送 tag 至 GitHub。请手动在网页端 Release 挂载 EXE！"
else
    echo -e "\n========== [步骤 4] 使用 GitHub CLI 自动发布 Release =========="
    gh release create "$VERSION" "dist/全景下载合成工具.exe" --title "$VERSION - 全景下载合成工具" --notes "🚀 这是自动打包发布的 $VERSION 版本二进制文件，供直接双击运行。"
    echo "🎉 自动打包与 GitHub Release 发布已圆满完成！"
fi

# 7. 自动切回 master 分支，恢复开发环境
echo -e "\n正在切回 master 开发分支，继续后续开发..."
git checkout master
