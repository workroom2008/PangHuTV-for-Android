# EcoHub for Android

[![Release](https://img.shields.io/github/v/release/workroom2008/EcoHub-for-Android)](https://github.com/workroom2008/EcoHub-for-Android/releases)
[![Download APK](https://img.shields.io/badge/Download-.apk-green?logo=android&logoColor=white)](https://github.com/workroom2008/EcoHub-for-Android/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)

[EcoHub](https://github.com/workroom2008/PangHuTV) 的 Android 原生客户端（基于 Flutter 构建）。

> **提示**：本仓库是 EcoHub 的纯客户端应用，**本身不提供、不存储任何影视资源**。安装后需配置 **服务端地址** 并用网站账号登录后方可浏览与观影。
> 
> 相关项目：[EcoHub 主仓库（服务端 + Web）](https://github.com/workroom2008/PangHuTV) · 移动端仅维护 **Android / iOS**（本 Flutter 工程）

---

## 📥 下载安装

- 🚀 **[下载最新版本 APK (Releases Latest)](https://github.com/workroom2008/EcoHub-for-Android/releases/latest)**
  - 现代主流 Android 手机请下载 `*-arm64-v8a.apk`（体积更小）
  - 较老机型请下载 `*-armeabi-v7a.apk`
- 📜 **[查看所有历史版本与更新日志](https://github.com/workroom2008/EcoHub-for-Android/releases)**

---

## 📡 服务端说明

客户端所有影视列表、分类、搜索、播放地址均由你接入的 **EcoHub 服务端** 提供。

### 1. 服务端从哪来？

- **自建部署（推荐）**  
  按照 [EcoHub 部署指南](https://github.com/workroom2008/PangHuTV/blob/main/docs/README-Deploy.md) 在你的服务器上部署 EcoHub 服务端。  
  部署成功后，在管理后台「工作台」点击「订阅地址」即可获取客户端订阅源：
  ```
  http://<你的服务器IP或域名>:3000/api/provide/app
  ```
  *(若配置了 HTTPS 或反向代理，格式为 `https://<你的域名>/api/provide/app`，亦兼容原 `/api` 路径)*。在管理后台完成影视数据采集后，客户端即可直接同步。

- **使用公共源 / 他人分享源**  
  如果你有朋友已经部署了 EcoHub 站点，或使用社区公开的 EcoHub 节点，可直接获取其服务端根地址填入（填入你部署的服务端根地址即可）。

### 2. 如何在 App 中配置？

1. 填写 **服务端根地址**（如 `http://192.168.1.250:3008` 或反代 `https://vod.example.com`，不要带 `/api/...`）；
2. 使用与 **网站相同的账号密码登录**（`POST /api/login`，Token 与 Web 共用）；
3. 登录后 App 会拉取 `/api/app/bootstrap`，后台新增采集源会自动出现在搜索/源列表中。

---

## 推荐

### 服务器

| 服务商 | 说明 | 链接 |
| --- | --- | --- |
| CloudCone | 1. 演示站点所用服务商<br>2. 高性价比 VPS，磁盘 I/O 不受限 | [前往选购](https://app.cloudcone.com/?ref=14393) |

### 网络服务

| 服务商 | 特点 / 价格 | 链接 |
| --- | --- | --- |
| 良心云 | 低至 2 元/月 <br>新用户注册即获体验流量 | [前往注册](https://xn--9kqz23b19z.com/#/register?code=xAmvfdic) |
| 赔钱机场 | 低至 1.5 元/月 <br>适合高流量与备用需求 | [前往注册](https://xn--mes358aby2apfg.com/register?code=FA4xlzHD&cover=sfw) |
| iKuuu | 老牌稳定机场 <br>新用户注册即获体验流量 | [前往注册](https://ikuuu.top/auth/register?code=Uubm) |

---

## 🛠️ 构建分工

| 平台 | 在哪里打 |
| --- | --- |
| **Android APK** | 本机 `D:\Android`（Flutter + SDK） |
| **iOS IPA** | 暂不在 CI 编译；需要时会再开启（workflow 保留，仅手动触发） |

本机目录约定：

- SDK：`D:\Android\Sdk`
- Flutter：`D:\Android\flutter`

### Android（本机）

```powershell
# 首次：复制 SDK 路径配置
copy app-for-android\android\local.properties.example app-for-android\android\local.properties

# 或直接运行脚本（会自动复制 local.properties）
app-for-android\scripts\build-apk-win.cmd
```

手动命令：

```powershell
$env:ANDROID_HOME = "D:\Android\Sdk"
$env:Path = "D:\Android\flutter\bin;" + $env:Path
cd app-for-android
flutter pub get
flutter run                    # 调试
flutter build apk --release --split-per-abi
```

产物：`build/app/outputs/flutter-apk/app-*-release.apk`

### iOS

当前 **不自动构建**。以后要发 iOS 时再说，可在子模块仓库 Actions 里手动跑 **Build Release (iOS IPA)**，或恢复 workflow 里的 `tags: v*.*.*` 触发。

---

## 📄 开源许可

本项目遵循 [PolyForm Noncommercial 1.0.0](https://github.com/workroom2008/PangHuTV/blob/main/LICENSE) 协议。
