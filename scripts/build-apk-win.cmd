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
call flutter build apk --release --split-per-abi
endlocal
