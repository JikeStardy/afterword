# 有下文 · Afterword 更名记录

日期：2026-09-27。分支：`chore/afterword-branding`。

## 更名范围

- 中文名「有下文」，英文名 Afterword，组合名称「有下文 · Afterword」。
- 中文标语「让每一次收藏，都有下文。」；英文标语「Save it. See where it leads.」。
- 更新 Flutter 应用标题、启动失败提示、Android/iOS 显示名、Android 通知名称、macOS 产品名及相关构建引用。
- 备份、日志和诊断包的新导出文件名前缀改为 `afterword-`，更新 README 与当前操作文档。
- 保留 `app.readlater.readlater`、Dart package、数据库路径、通知通道 ID、原生桥接和内部类名。旧备份仍按内容恢复，不依赖文件名前缀。历史需求、交付记录和原安装包文件名保留。
- 本次未新增依赖或修改业务流程、数据格式及版本号，仍为 `0.3.1+4`。

## 验证

| 检查 | 本次结果 |
| --- | --- |
| `bash tool/check.sh android` | 通过：Dart 格式、静态分析、13 个 Git 钩子场景、288 项单元／Widget 测试、Android arm64 release 构建；锁文件无变化 |
| `flutter test integration_test/device_flow_test.dart -d emulator-5580` | 通过：专用 API 36 arm64 模拟器，本地受控夹具；覆盖 SQLite、HTTP、PDF、诊断、生命周期、界面及备份恢复 |
| release 安装与冷启动 | `adb install -r` 成功，启动状态 `ok`，首页截图已检查 |
| Android 品牌 | APK 元数据和系统应用信息页显示「有下文」；四个原通知通道保留 ID，名称使用新品牌 |
| Apple 配置 | iOS/macOS Info.plist、macOS project.pbxproj 均通过 `plutil -lint`；产品、Scheme 与测试宿主路径经静态核对一致 |
| 独立审查 | code-reviewer 与 kotlin-reviewer 均未发现阻塞问题 |

原始日志与截图保存在忽略目录 `dist/afterword-branding/`。iOS/macOS 未构建或运行验收；Android 验证使用模拟器和测试服务，不代表真机或真实供应商验证。

## 本地测试产物

- `dist/Afterword-0.3.1-android-arm64.apk`，沿用个人测试签名，未公开发布。
- SHA-256：`4b091f26163b8778ce281149e0f0f5d7680c5bd07b0f7bdfe9eac248bd3aa0e1`。
- 保留原有 `Readlater-0.3.1-android-arm64.apk`；本次新名称产物单独保存。
