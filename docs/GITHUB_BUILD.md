# GitHub Android 构建

仓库：[JikeStardy/afterword](https://github.com/JikeStardy/afterword)。主分支：`main`。
配置：[android.yml](../.github/workflows/android.yml)。

## 触发与下载

- 推送 main：检查已整合代码并生成 APK。
- Pull Request → main：检查 PR 合并结果，无签名 Secret。
- Actions → Android → Run workflow：按需验证所选分支；仅 main 可读取固定签名。

在 [workflow](https://github.com/JikeStardy/afterword/actions/workflows/android.yml) 的成功运行中，打开构建摘要的「Android 安装包下载」，或滚动到 Artifacts。每次构建分别上传四个独立文件，保留 14 天：

- `Afterword-<version>-android-arm64.apk`：安装包，下载后直接安装，无需解压。
- `SHA256SUMS.txt`：APK 的 SHA-256 校验值。
- `SIGNATURE.txt`：APK 的公开签名证书信息。
- `BUILD_INFO.txt`：版本、源码提交、签名模式和 Flutter 版本。

使用 `upload-artifact v7` 的 `archive: false`，每个文件作为一条 artifact，名称就是文件名。将 APK 与 `SHA256SUMS.txt` 保存到同一目录后，可运行 `sha256sum --check SHA256SUMS.txt`（macOS 使用 `shasum -a 256 -c SHA256SUMS.txt`）核对下载完整性。

Actions artifact 即使来自公开仓库，也需要登录 GitHub 才能下载。拆分文件不会改变登录要求；需要免登录的公开下载链接时，另行发布测试 Release。此 workflow 不自动创建 GitHub Release 或打标签。此前的历史构建仍保留原来的 ZIP 附件。

## 检查与工具链

固定 Ubuntu 24.04、Flutter 3.47.5 / Dart 3.13.4、JDK 21、Node.js 24、Android SDK 36、Build Tools 36.0.0、NDK 28.2.13676358；使用仓库 Gradle Wrapper。Flutter Linux 官方归档同时验证 SHA-256 和 Git revision，Actions 固定完整提交 SHA。

依次运行 `flutter pub get --enforce-lockfile`、`bash tool/check.sh android` 和诊断接收器的 Node 测试。包含格式、静态分析、Git 钩子行为、全部单元/Widget 测试和 release 构建；任何失败阻止 APK 上传。artifact 上传缺文件同样失败。

CI 在 runner 临时目录配置 Gradle 最大 3 GiB 堆、1 GiB metaspace 和 2 个 worker，不更改开发者本地配置。普通 CI 仅有 `contents: read`，不保留 checkout 凭据，不使用模型或搜索 API Key。相同 PR/分支的新运行取消过时运行。

云端构建不执行手机模拟器测试；本地设备流程和真实供应商验收仍按项目规范执行。

## 签名与覆盖升级

项目目前使用个人测试用 debug signingConfig，不是应用商店签名。Android 同包名覆盖安装要求签名证书一致。

- 仓库 Secret 名为 `ANDROID_DEBUG_KEYSTORE_BASE64`，内容为当前已交付 APK 对应测试 keystore 的 Base64。设置前须由密钥持有人明确授权。
- 仅 `main` 的 push / 手动构建注入该 Secret，恢复到 runner 临时目录的 `ANDROID_USER_HOME/debug.keystore`。workflow 为 Android SDK 准备及后续构建步骤显式设置同一个 `ANDROID_USER_HOME`，避免 runner 的 XDG 配置改变 Gradle 默认密钥位置；不会把私钥提交到 Git 或放进 artifact。
- PR 和其他分支不读取 Secret；main 未配置 Secret 时也使用临时测试签名。`BUILD_INFO.txt` 和 Actions Summary 会标记 `fixed-personal-test` 或 `temporary-test`。
- 固定签名构建在上传前强制比对 APK 证书与恢复的 keystore 证书，不一致则构建失败。也可核对 `SIGNATURE.txt` 与原安装包一致。目前本地已交付证书 SHA-256 为 `72ec97d8ec30dd3efbc4a2bcfbd1843115b75a7ae14ae8b412b97cc0ab8e5de2`。
- 临时签名通常不能覆盖原安装包。先导出备份，不把卸载旧版作为自动升级步骤。

现有 debug keystore 的标准 alias/password 用于兼容个人测试构建；真正私钥始终仅通过 Secret 传递。以后如需公开正式发行，应另立正式签名、备份与迁移方案。

## 首次接入验证

本次在功能分支完成配置和检查后，将整合后的最新代码快进到本地 main 并推送。远端原有 MIT LICENSE 的初始化历史保留，使用普通快进推送，不重写远端历史。

验收记录须区分本地检查与实际 Actions 结果；只有云端成功运行并取得 APK，才能确认云端构建已通过。签名 Secret 与首次运行状态以最终交付记录为准。

2026-09-27 本地接入验证：actionlint 1.7.12 通过；独立代码审查通过；`bash tool/check.sh android` 通过（格式、静态分析、13 个 Git 钩子场景、288 项单元/Widget 测试及 arm64 release 构建）；诊断接收器 8 项测试通过。此记录不代表云端构建通过；云端运行链接和产物在首次推送后核对。

## 官方依据

- [Flutter 官方 Linux 发布索引](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
- [GitHub workflow 触发事件](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
- [GitHub Actions 构建附件下载](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
- [upload-artifact 单文件直接上传](https://github.com/actions/upload-artifact#upload-an-individual-file-unzipped)
- [Android 应用签名](https://developer.android.com/studio/publish/app-signing)
