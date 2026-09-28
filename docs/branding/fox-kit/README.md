# 有下文 · 长尾狐设计包

基于九宫格 **07 长尾狐**，按“功能识别优先、狐狸用于品牌与状态”的方向制作。交付可编辑 SVG 与可播放样册，本轮没有接入 App。

包含 **85 个功能图标、5 个导航选中变体、17 个场景、4 份品牌文件、8 种动效**。当前 App 的 82 个 Material 图标名称全部有映射。

**[打开离线样册](index.html)**：双击 `index.html` 即可使用；文件需与相邻 JS / CSS 一同保留。无需安装、联网或启动服务器。可筛选图标、切换尺寸与颜色、下载单个 SVG，并播放、暂停、重播动效。

## 文件与修改入口

| 文件 | 用途 |
| --- | --- |
| `brand/` | 正色、反白、圆角底板、可动画分层主形 |
| `icons/` | 功能图标；`-selected` 为五个导航的选中版本 |
| `scenes/` | 17 个空态及运行状态插画 |
| [icons.js](icons.js) | 图标原始矢量、语义、分类及 Material 映射 |
| [scenes.js](scenes.js) | 狐狸分层矢量、场景与 8 种动效参数 |
| [preview.js](preview.js) | 实际可播放的浏览器动效与交互实现 |
| [DESIGN.md](DESIGN.md) | 比例、颜色、使用边界与动效规范 |
| [catalog.json](catalog.json) / [coverage.json](coverage.json) | 机器可读目录、原 App 图标引用与覆盖结果 |
| [reference/fox-master.png](reference/fox-master.png) | 原始生成参考；[提示词](prompts/fox-master.txt) |

SVG 均可直接编辑路径，不依赖字体、位图或远程资源。品牌主形保留侧身坐姿、尖耳、向右的脸，以及上卷环抱的长尾。原 PNG 是 imagegen 整理的概念参考；本套 SVG 为依据其轮廓重绘的分层设计。

## 重新导出

在项目根目录用已有 Node.js 运行：

```sh
node docs/branding/fox-kit/build-assets.cjs
```

修改 `icons.js` / `scenes.js` 后执行此命令，会更新独立 SVG、目录和覆盖表。脚本读取仓库 `lib/` 核对实际 Material 引用，覆盖缺失应先补齐再交付。打包后的独立目录可以直接预览；重新核对 App 覆盖则需在完整仓库中运行。

静态 SVG 不内嵌动画。可复用的动效时序在 `scenes.js`，运动关键帧在 `preview.js`；后续接入 Flutter 时按相同事件、幅度、时长转换。App 内的实际尺寸、屏幕阅读器标签、系统减少动态偏好与平台启动图标资源留待接入阶段验证。

## 验证

[本次验证记录](VERIFICATION.md) 说明实际运行的检查和范围。`verify-preview.cjs` 是开发者可选的浏览器验证脚本，使用环境中已有的 Playwright 与 Chromium，不是打开样册所需的依赖。可通过 `NODE_PATH` 指向已有 Playwright，通过 `BROWSER_EXECUTABLE` 指定已安装的浏览器，然后运行：

```sh
node docs/branding/fox-kit/verify-preview.cjs
```

截图和检查结果写入仓库忽略的 `dist/fox-kit-validation/`，不混入 SVG 资产。
