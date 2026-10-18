@echo off
setlocal
set "ROOT=%~dp0.."
set "ANDROID_HOME=D:\Android\Sdk"
set "PATH=D:\Android\flutter\bin;%PATH%"
set "HTTP_PROXY=http://192.168.1.250:20172"
set "HTTPS_PROXY=http://192.168.1.250:20172"
set "http_proxy=http://192.168.1.250:20172"
set "https_proxy=http://192.168.1.250:20172"
set "NO_PROXY=localhost,127.0.0.1,::1"
set "no_proxy=localhost,127.0.0.1,::1"
cd /d "%ROOT%"
if not exist "android\local.properties" (
  copy /Y "android\local.properties.example" "android\local.properties" >nul
  echo [build] 已生成 android\local.properties
)
call flutter pub get
rem 仅 arm64 真机包，不产出 armeabi-v7a / x86_64
call flutter build apk --release --target-platform android-arm64
rem Gradle 实际输出在 apk\release，统一拷到 flutter-apk 固定名，避免找错旧包
if exist "build\app\outputs\apk\release\app-release.apk" (
  copy /Y "build\app\outputs\apk\release\app-release.apk" "build\app\outputs\flutter-apk\app-release.apk" >nul
  echo [build] 产物：build\app\outputs\flutter-apk\app-release.apk
)
endlocal
