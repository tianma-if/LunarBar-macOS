# LunarBar

LunarBar 是一个轻量级、原生风格的 macOS 菜单栏月历应用。它的目标是在顶部菜单栏中提供一个精致的悬浮面板，集中展示公历日历、中国农历、二十四节气、法定节假日及调休补班标签，以及实时天气。

项目目前处于早期开发阶段。当前已经完成 Step 1：应用入口、菜单栏常驻、隐藏 Dock 图标，以及基础的 7 x 6 日历网格。

## 功能特性

- 使用 macOS 15+ 的 `MenuBarExtra` 实现原生菜单栏应用
- 通过 `LSUIElement` 隐藏 Dock 图标
- 使用 `.menuBarExtraStyle(.window)` 弹出悬浮窗口
- 完全使用 SwiftUI 构建界面
- 采用 MVVM 风格组织代码
- 自绘 7 x 6 月历网格，包含上月和下月补白日期
- 显示中国农历日期、传统节日和二十四节气
- 显示 2026 年中国法定节假日和调休补班角标
- 显示实时天气，并支持配置高德天气或 QWeather API Key
- 周一作为每周起始日，更贴近中文用户习惯
- 基础样式支持深色模式
- 已配置 GitHub Actions 云端 macOS 构建

## 开发路线

- Step 1：创建 macOS 菜单栏应用和基础日历网格
- Step 2：集成中国农历和二十四节气
- Step 3：接入法定节假日和调休补班角标
- Step 4：实现天气卡片和 API Key 设置界面

## 运行要求

- macOS 15 或更高版本
- 本地开发需要 Xcode 15 或更高版本

如果只是下载 GitHub Actions 生成的构建产物进行体验，不需要安装 Xcode。但如果要在本地开发、调试和运行源码，仍然需要完整 Xcode。

## 项目结构

```text
App/
  LunarBarApp.swift
Models/
  DayInfo.swift
  WeatherInfo.swift
ViewModels/
  CalendarViewModel.swift
  WeatherViewModel.swift
Views/
  MainPopupView.swift
  WeatherSettingsView.swift
  Components/
    CalendarGridView.swift
    WeatherHeaderView.swift
Services/
  HolidayService.swift
  WeatherService.swift
workers/
  weather/
    src/
      index.ts
    wrangler.jsonc
Resources/
  Info.plist
  holidays.json
.github/
  workflows/
    macos-build.yml
```

## 本地构建

打开 Xcode 工程：

```bash
open LunarBar.xcodeproj
```

然后在 Xcode 中选择 `LunarBar` scheme，运行目标选择 `My Mac`，点击运行即可。

如果已经安装并选择了完整 Xcode，也可以使用命令行构建：

```bash
xcodebuild \
  -project LunarBar.xcodeproj \
  -scheme LunarBar \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## 使用 GitHub Actions 云端构建

本仓库已经配置了 macOS GitHub Actions workflow。每次推送到 `main` 分支时，GitHub 会在云端使用 Xcode 构建应用，并上传一个 debug 版本的 `.app` 压缩包。

下载云端构建产物：

1. 打开 GitHub 仓库页面。
2. 进入 `Actions` 标签页。
3. 选择最新的 `macOS Build` 运行记录。
4. 在页面底部下载 `LunarBar-debug` artifact。
5. 解压后运行 `LunarBar.app`。

由于 GitHub Actions 生成的是未经过 Developer ID 签名和 notarization 公证的 debug 构建，macOS 第一次打开时可能会拦截。可以右键点击 App 后选择“打开”，也可以移除 quarantine 属性：

```bash
xattr -dr com.apple.quarantine /path/to/LunarBar.app
```

## 当前状态

当前版本可以在菜单栏显示日历图标，并弹出带农历、传统节日、二十四节气、法定节假日、调休补班角标和实时天气的基础月历面板。天气通过项目的 Cloudflare Worker 代理获取，用户不需要配置天气服务商 API Key。

## 天气后端

仓库包含一个 Cloudflare Worker 天气代理，位于 `workers/weather`。它提供统一天气接口，并通过 KV 缓存天气数据，避免客户端直接持有天气服务商密钥。

当前已支持：

- QWeather JWT 认证
- Open-Meteo 免 Key fallback
- Cloudflare KV 缓存

示例：

```text
https://lunarbar-weather.yingwaizhiying8671.workers.dev/weather?lat=39.9042&lon=116.4074&cityName=北京
```

## 许可证

暂未选择许可证。
