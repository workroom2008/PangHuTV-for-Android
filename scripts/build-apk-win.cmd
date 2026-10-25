@echo off
rem ============================================================
rem 胖虎TV（app-for-tv / OrionTV fork）Android APK 构建脚本
rem !! 仅在用户明确指令后运行（AGENTS.md 3.4.1） !!
rem 前置：node + corepack(yarn 1.22)、JDK 17/21、Android SDK + NDK
rem ============================================================
setlocal
cd /d "%~dp0.."

echo [1/3] expo prebuild（TV 模式，重新生成 android/）
call corepack yarn prebuild
if errorlevel 1 exit /b 1

echo [2/3] 拷贝 TV manifest 等覆盖配置
call corepack yarn copy-config
if errorlevel 1 exit /b 1

echo [3/3] gradle assembleRelease
cd android
call gradlew.bat assembleRelease
if errorlevel 1 exit /b 1

echo.
echo 完成：android\app\build\outputs\apk\release\app-release.apk
endlocal
