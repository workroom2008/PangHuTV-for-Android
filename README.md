# 胖虎影视 for Android

[![Release](https://img.shields.io/github/v/release/workroom2008/PangHuTV-for-Android)](https://github.com/workroom2008/PangHuTV-for-Android/releases)
[![Download APK](https://img.shields.io/badge/Download-.apk-green?logo=android&logoColor=white)](https://github.com/workroom2008/PangHuTV-for-Android/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)

[胖虎影视（PangHuTV）](https://github.com/workroom2008/PangHuTV) 的 Android 原生客户端（基于 Flutter 构建）。

> **提示**：本仓库是胖虎影视的纯客户端应用，**本身不提供、不存储任何影视资源**。安装后需配置 **服务端地址** 并用网站账号登录后方可浏览与观影。
> 
> 相关项目：[胖虎影视主仓库（服务端 + Web）](https://github.com/workroom2008/PangHuTV) · 移动端 **Android / iOS**（本 Flutter 工程）

---

## 📥 下载安装

- 🚀 **[下载最新版本 APK (Releases Latest)](https://github.com/workroom2008/PangHuTV-for-Android/releases/latest)**
  - 现代主流 Android 手机请下载 `*-arm64-v8a.apk`（体积更小）
  - 较老机型请下载 `*-armeabi-v7a.apk`
- 📜 **[查看所有历史版本与更新日志](https://github.com/workroom2008/PangHuTV-for-Android/releases)**

---

## 📡 服务端说明

客户端所有影视列表、分类、搜索、播放地址均由你接入的 **胖虎影视服务端** 提供。

### 1. 服务端从哪来？

- **自建部署（推荐）**  
  按照 [胖虎影视部署指南](https://github.com/workroom2008/PangHuTV/blob/main/docs/README-Deploy.md) 在你的服务器上部署服务端。  
  部署成功后，在管理后台「工作台」点击「订阅地址」即可获取客户端订阅源：
  ```
  http://<你的服务器IP或域名>:3000/api/provide/app
  ```
  *(若配置了 HTTPS 或反向代理，格式为 `https://<你的域名>/api/provide/app`，亦兼容原 `/api` 路径)*。在管理后台完成影视数据采集后，客户端即可直接同步。

- **使用公共源 / 他人分享源**  
  若已有他人部署的胖虎影视站点，可直接获取其服务端根地址填入（填入你部署的服务端根地址即可）。

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

**不要主动构建**：仅当明确说「打 APK / 发 iOS / 构建客户端」等指令后再执行；且 **本机 for-Android 已 commit 并 push 到 GitHub** 与远程同版，再本机构 Android 或触发 iOS workflow。

| 平台 | 在哪里打 |
| --- | --- |
| **Android APK** | **本机 Windows**（`D:\Android`，见下） |
| **iOS IPA** | **GitHub Actions `macos-latest`**（[PangHuTV-for-Android](https://github.com/workroom2008/PangHuTV-for-Android) **public**，手动触发 workflow） |

> **Actions 额度**：Android 不占 GitHub 分钟（本机构建）。iOS 依赖 **公开库** 的标准 macOS runner（私有库 macOS 乘数高，易耗尽额度）。
>
> **NAS（飞牛 Linux）不能打 IPA**：没有 Xcode，Docker 镜像也无法替代 macOS 签名链。胖虎 Docker 镜像只在 NAS 上构建 **服务端**；移动端与 NAS 解耦。

本机目录约定：

- SDK：`D:\Android\Sdk`
- Flutter：`D:\Android\flutter`

### Android（本机）

```powershell
# 首次：复制 SDK 路径配置
copy app-for-android\android\local.properties.example app-for-android\android\local.properties

# 推荐：一键 release（走 NAS 代理拉依赖）
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

### iOS（远程 macOS：GitHub Actions）

1. 将 `app-for-android` 改动 push 到 [PangHuTV-for-Android](https://github.com/workroom2008/PangHuTV-for-Android)（本目录为独立 Git 仓库）。
2. 本机执行（需 `gh auth login`）：

```powershell
app-for-android\scripts\trigger-ios-ipa-gh.cmd
```

或：`gh workflow run build-release.yml -R workroom2008/PangHuTV-for-Android`

3. 在 GitHub → Actions → **Build Release (iOS IPA)** → 最新 run → 下载 Artifact **`ecohub-ipa`**（`--no-codesign` 组包，侧载/TestFlight 需自行在 Mac 上重签）。

打 tag `v*.*.*` 并 push 后，可恢复 workflow 里 `push.tags` 以自动挂 Release（当前默认仅 `workflow_dispatch`）。

---

## 📄 开源许可

本项目遵循 [PolyForm Noncommercial 1.0.0](https://github.com/workroom2008/PangHuTV/blob/main/LICENSE) 协议。
