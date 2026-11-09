@echo off
setlocal
set "ROOT=%~dp0.."
set "ANDROID_HOME=D:\Android\Sdk"
set "PATH=D:\Android\flutter\bin;%PATH%"
rem Gradle 需要 JDK；本机只有 Android Studio 自带 jbr，不设 JAVA_HOME 会直接
rem "JAVA_HOME is not set"，后续 copy 还会误报「产物」已生成。
if not defined JAVA_HOME (
  if exist "D:\Android\Android Studio\jbr\bin\java.exe" set "JAVA_HOME=D:\Android\Android Studio\jbr"
)
if not defined JAVA_HOME (
  echo [build] 未找到 JDK，请设置 JAVA_HOME 后重试
  exit /b 1
)
set "PATH=%JAVA_HOME%\bin;%PATH%"
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
if errorlevel 1 (
  echo [build] 构建失败，未产出 APK
  exit /b 1
)
rem Gradle 实际输出在 apk\release，统一拷到 flutter-apk 固定名，避免找错旧包
if exist "build\app\outputs\apk\release\app-release.apk" (
  copy /Y "build\app\outputs\apk\release\app-release.apk" "build\app\outputs\flutter-apk\app-release.apk" >nul
  echo [build] 产物：build\app\outputs\flutter-apk\app-release.apk
) else (
  echo [build] 未找到 Gradle 输出 APK
  exit /b 1
)
endlocal

