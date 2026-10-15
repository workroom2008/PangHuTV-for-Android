@echo off
setlocal
REM iOS 必须 macOS + Xcode；飞牛 NAS 为 Linux，无法 flutter build ipa。
REM 本脚本在 GitHub Actions（macos-latest）上手动触发 Build Release (iOS IPA)，产物在 Actions Artifacts。
set "REPO=workroom2008/PangHuTV-for-Android"
set "WORKFLOW=build-release.yml"
where gh >nul 2>&1
if errorlevel 1 (
  echo [ipa] 未找到 gh，请先安装 GitHub CLI 并 gh auth login
  exit /b 1
)
echo [ipa] 触发 %REPO% workflow: %WORKFLOW%
gh workflow run "%WORKFLOW%" -R "%REPO%"
if errorlevel 1 exit /b 1
echo [ipa] 已提交队列。查看: gh run list -R %REPO% --workflow=%WORKFLOW%
echo [ipa] 下载: gh run download -R %REPO% （选最新 run 的 ecohub-ipa 产物）
endlocal
