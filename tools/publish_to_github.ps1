# =============================================================================
# publish_to_github.ps1 —— 把本仓库提交并推送到 GitHub
#
# 用法（在 PowerShell 里运行）：
#   cd D:\FPGA比赛
#   powershell -ExecutionPolicy Bypass -File tools\publish_to_github.ps1
#
# 需要先准备：
#   1. GitHub 账号，并已在网页上创建一个空仓库（不要勾选 README/gitignore/license）
#   2. Personal Access Token（PAT）：GitHub → Settings → Developer settings
#      → Personal access tokens → Tokens (classic) → Generate new token
#      勾选 repo 权限，复制生成的 ghp_xxxxx
# =============================================================================

$ErrorActionPreference = 'Stop'
$repoDir = Split-Path $PSScriptRoot -Parent
Set-Location $repoDir

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " 发布到 GitHub" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " 仓库目录: $repoDir"
Write-Host ""

# ---------- 找 git ----------
$git = $null
foreach ($c in @("$env:ProgramFiles\Git\cmd\git.exe",
                 "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
                 "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
    if (Test-Path $c) { $git = $c; break }
}
if (-not $git) {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { $git = $cmd.Source }
}
if (-not $git) {
    Write-Host "找不到 git，请先安装：https://git-scm.com/download/win" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}
Write-Host " git: $git" -ForegroundColor Green

# ---------- 收集信息 ----------
$user  = Read-Host "请输入 GitHub 用户名（例如 zhang-san）"
$email = Read-Host "请输入提交用邮箱（建议 用户名@users.noreply.github.com）"
$repo  = Read-Host "请输入你在 GitHub 上创建的仓库名（例如 zynq7010-image-filter）"

if (-not $user -or -not $email -or -not $repo) {
    Write-Host "信息不完整，退出。" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

# ---------- 配置身份（只对本仓库生效，不改全局） ----------
& $git config user.name  $user
& $git config user.email $email
Write-Host " 提交身份: $user <$email>" -ForegroundColor Green

# ---------- 提交 ----------
$hasCommit = (& $git rev-parse --verify HEAD 2>$null)
if (-not $hasCommit) {
    & $git add -A
    & $git commit -m "Initial commit: ZYNQ-7010 real-time image filtering accelerator" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "提交失败" -ForegroundColor Red; Read-Host "按回车退出"; exit 1 }
    Write-Host " 已创建首次提交" -ForegroundColor Green
} else {
    Write-Host " 已有提交历史，跳过首次提交" -ForegroundColor Yellow
}

# ---------- 远端 ----------
$remoteUrl = "https://github.com/$user/$repo.git"
$existing = & $git remote 2>$null
if ($existing -contains 'origin') {
    & $git remote set-url origin $remoteUrl
} else {
    & $git remote add origin $remoteUrl
}
Write-Host " 远端: $remoteUrl" -ForegroundColor Green

# ---------- 推送 ----------
Write-Host ""
Write-Host " 需要 Personal Access Token（ghp_ 开头）。" -ForegroundColor Yellow
Write-Host " 生成方法：GitHub → Settings → Developer settings → Personal access tokens" -ForegroundColor Yellow
Write-Host "          → Tokens (classic) → Generate new token → 勾选 repo 权限" -ForegroundColor Yellow
Write-Host ""
$token = Read-Host " 粘贴 token（输入时不显示）" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))

Write-Host ""
Write-Host " 正在推送……（第一次可能要 1~2 分钟）" -ForegroundColor Cyan
# token 只用于本次推送，不写进 .git/config
& $git push "https://$user`:$plain@github.com/$user/$repo.git" "main:main" --force
$ok = ($LASTEXITCODE -eq 0)

if ($ok) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host " 推送成功！" -ForegroundColor Green
    Write-Host " 仓库地址: https://github.com/$user/$repo" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "推送失败。常见原因：" -ForegroundColor Red
    Write-Host "  1. 用户名/仓库名拼错（注意 GitHub 仓库名大小写）"
    Write-Host "  2. token 过期或没有 repo 权限"
    Write-Host "  3. 网页上创建仓库时勾选了 README/gitignore，导致远端已有提交"
    Write-Host "     解决：先运行  git pull --rebase origin main  再重试"
    Write-Host "  4. 网络问题（国内访问 GitHub 不稳定），可换用 Gitee 或开代理"
}

Write-Host ""
Read-Host "按回车退出"
