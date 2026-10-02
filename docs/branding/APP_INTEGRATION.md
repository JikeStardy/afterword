# 有下文 · 长尾狐 App 接入记录

日期：2026-09-28。分支：`feat/fox-app-integration`。

本轮把长尾狐设计包接入 Flutter/Android。历史设计验证仍以 [fox-kit/VERIFICATION.md](fox-kit/VERIFICATION.md) 为准；其中“未接入 App”的描述记录的是设计包交付时状态，不作为当前接入结果。

## Flutter 接入范围

- 使用原生 Canvas 绘制矢量，不新增运行依赖。
- 生成 98 个 Material 别名映射，覆盖 App 当前 UI 图标引用。
- 接入 85 个功能图标、5 个导航选中态、17 个场景插画和品牌 fox。
- App 显式图标引用替换为 Afterword 图标层；底部 5 个 tab 显式使用 selected 资源。复选框、日期选择器等框架内部控件保留系统行为。
- EmptyState 显式指定场景；成功反馈和研究完成态使用真实 `complete` 状态。
- 动效默认播放一次；后台、`TickerMode` 关闭和系统减少动态时停止。

## Android 接入范围

- 生成 legacy 5 档 launcher PNG。
- 生成 Android v26 自适应图标、v33 单色图标、启动图标和通知图标。
- 资源适配 Android mask 安全圈；Kotlin/Android 资源独立 review 后修复过裁切问题。

## 生成命令

```sh
node tool/generate_afterword_vectors.cjs
node tool/generate_afterword_vectors.cjs --check
node tool/generate_afterword_platform_icons.cjs
node tool/generate_afterword_platform_icons.cjs --check
```

Flutter 矢量生成器需要本机 Dart/Flutter 环境，可通过 `DART_BIN` 或 `FLUTTER_BIN` 指定；Android XML 生成器只需要 Node.js。可选的 legacy PNG 重新生成：

```sh
NODE_PATH=<playwright-node-modules> \
BROWSER_EXECUTABLE=<chrome-path> \
node tool/generate_afterword_platform_icons.cjs --raster
```

`--raster` 需要可用 Playwright 与 Chrome；普通生成和 XML 检查不需要它。当前 PNG 已随源码提交。它们与 XML 来自同一狐狸母版。

## 本轮验证

- `bash tool/check.sh android` 通过：格式检查、静态分析、13 个 Git 钩子场景、303 项 Flutter 单元／Widget 测试、Android arm64 release 构建。锁文件未变化。
- 新增的 15 项 Flutter 专项测试覆盖矢量绘制、主题和语义、一次／循环播放、后台暂停、减少动态、导航和研究状态。既有矩阵覆盖三种阅读外观、320/390/430 宽度与 1.0/1.8 文字缩放。
- `node --test tool/generate_afterword_vectors.test.cjs tool/generate_afterword_platform_icons.test.cjs`：12 项通过；两个生成器的 `--check` 均通过。
- Flutter、JavaScript 生成器、Kotlin/Android 资源均经独立审查。已修复菜单同时指定 `child/icon` 的断言、圆形遮罩裁切及 SVG 子路径起点／变换顺序／属性继承问题。
- 专用 Android API 36 arm64 模拟器执行 `fox_branding_test.dart`、`reading_design_test.dart`、`device_flow_test.dart` 均通过；阅读测试保留 21 张截图，验证三种外观、证据往返与原文文字选择。
- 最终 release APK 安装成功、签名验证通过；实看桌面圆形图标与冷启动图无裁切。版本保留 `0.3.1+4`，使用现有个人测试签名，不作为新版本发布。

工具链：Flutter 3.47.5 / Dart 3.13.4、Node.js 24.14.1、JDK 21、Android SDK 36。模拟器显示覆盖值为 1080×1920、440dpi（约 393dp 宽）。原始日志和完整截图保存在忽略目录 `dist/fox-app-integration/`。

精选设备截图：[今日](screenshots/app-today.png)、[资料](screenshots/app-library.png)、[研究完成](screenshots/app-research-complete.png)、[Android 桌面](screenshots/android-launcher.png)、[冷启动](screenshots/android-splash.png)。

设备视觉测试可复现：

```sh
READLATER_SCREENSHOT_DIR=dist/fox-app-integration/device-screens \
flutter drive --driver=test_driver/device_screenshots.dart \
  --target=integration_test/fox_branding_test.dart -d <dedicated-test-device>
```

## 验证边界

设备测试使用隔离资料和本地协议夹具，没有调用真实模型供应商。未验证实体手机、其他 Android 版本和厂商桌面；通知图标已编译并审查资源引用，未逐个通知渠道截图验收。iOS/macOS 的平台图标未更新、未构建验收。没有合并 main、推送代码或发布。
