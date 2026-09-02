# LookSize

LookSize 是一个原生 macOS 菜单栏工具。在 Finder 中按空格打开 Quick Look 时，系统继续显示原文件名，LookSize 在文件名右侧补充媒体信息：

```text
4032×3024
3840×2160 · 59.94 fps
```

它采用视觉悬浮层，不修改 Finder、Quick Look、媒体文件或系统进程。

## 当前状态

- 版本：0.1.7
- 最低系统：macOS 13
- 已构建验证：macOS 15.7.9、Intel x86_64
- Apple Silicon：arm64 交叉编译通过，`dist/LookSize.app` 当前为 x86_64 + arm64 通用二进制
- 图片元数据：ImageIO
- 视频元数据：优先使用可选的 `ffprobe`，不可用时回退到 AVFoundation
- Finder 文件识别：Accessibility API
- Quick Look 窗口识别：Accessibility 首次定位 + CGWindowList 窗口 ID 高频跟踪

## 功能

- 图片：显示按 EXIF 方向修正后的像素尺寸。
- 视频：显示旋转修正后的分辨率和帧率。
- 保留 23.976、29.97、59.94 等常用小数帧率，不四舍五入成整数。
- 安装了 `ffprobe` 时，可读取 MKV、WebM 等更多格式，并在明显可变帧率时标记 `VFR`。
- 系统文件名保持原样，只显示分辨率和视频帧率。
- 通过 Accessibility 读取系统文件名的真实位置，将无背景、无边框的悬浮文字追加在右侧。
- 标题栏空间不足时自动移到预览内容左上角，并使用无边框半透明底色保证可读性。
- Quick Look 移动期间以 30 Hz 跟随，缩放后重新锚定系统文件名。
- 仅在 Finder 位于前台时允许显示；关闭预览或切换应用后立即移除且不会被残留窗口重新触发。
- 菜单栏可暂停监控、查看权限和当前文件。
- 自动检测辅助功能与 Finder 自动化授权状态，并提供“授权诊断与修复”入口。
- 读取桌面、文稿、下载、网络磁盘或移动磁盘时，显示对应的系统文件访问用途说明。

## 构建

只需安装 Xcode Command Line Tools，不需要完整 Xcode：

```bash
git clone https://github.com/kirawjl/LookSize.git
cd LookSize
./scripts/build-app.sh
open dist/LookSize.app
```

生成 Intel + Apple Silicon 通用二进制：

```bash
UNIVERSAL=1 ./scripts/build-app.sh
```

## 制作 macOS 安装包（免费方案）

不加入付费 Apple Developer Program 也可以生成标准 DMG（Disk Image，磁盘映像）安装包：

```bash
./scripts/build-dmg.sh
```

脚本默认重新构建 Intel + Apple Silicon 通用 App，并生成：

```text
dist/LookSize-0.1.7-universal.dmg
dist/LookSize-0.1.7-universal.dmg.sha256
```

安装步骤：

1. 双击 DMG。
2. 将 `LookSize.app` 拖到 `Applications`。
3. 首次打开如果被 macOS 拦截，先尝试打开一次，再进入：
   `系统设置 → 隐私与安全性 → 安全性 → 仍要打开`。
4. 按提示授予辅助功能和 Finder 自动化权限。

免费方案采用临时签名（Ad Hoc Signing），不具备 Developer ID 签名和 Apple 公证（Notarization）。因此从浏览器或网盘下载到其他 Mac 后，首次打开会出现安全提示；这是免费方案无法消除的系统限制。只应安装来自可信来源且 SHA-256 校验值一致的安装包，不要全局关闭 Gatekeeper。

如只为当前 Mac 构建较小的单架构安装包：

```bash
UNIVERSAL=0 ./scripts/build-dmg.sh
```

如复用已有的 `dist/LookSize.app`：

```bash
REBUILD=0 ./scripts/build-dmg.sh
```

正常使用需要两项核心授权：

```text
系统设置 → 隐私与安全性 → 辅助功能 → LookSize
系统设置 → 隐私与安全性 → 自动化 → LookSize → Finder
```

- **辅助功能（Accessibility）**：读取 Finder 与 Quick Look 的窗口、选中项和文件名位置，是显示悬浮信息的必要权限。
- **Finder 自动化（Automation / Apple Events）**：在辅助功能接口暂时无法取得 Finder 选择时读取当前文件路径，是稳定识别预览文件所需的兜底权限。
- **文件与文件夹（Files and Folders）**：只有媒体位于桌面、文稿、下载、网络磁盘或移动磁盘等受保护位置时，macOS 才会按需询问；不需要预先逐项授权。
- **屏幕录制（Screen Recording）**：不需要。LookSize 不截取屏幕像素，只读取窗口元数据与辅助功能元素。

菜单栏会自动刷新前两项权限状态。选择“授权诊断与修复…”可查看当前运行路径、请求缺失权限并打开对应系统设置。

首次读取 Finder 选择时，系统会询问“LookSize 想控制 Finder”，请选择“允许”。LookSize 只读取当前选中文件路径，不执行改名、移动、删除或写入操作。

授权后如果没有立即生效，退出并重新启动 LookSize。

如果替换更新 App 后，系统设置中已有 LookSize，但菜单仍显示“未授权”，请先在对应权限列表中删除旧 LookSize，再重新打开 `/Applications/LookSize.app` 并授权。默认免费构建采用临时签名（Ad Hoc Signing），每次二进制变化都会产生新的代码身份，macOS 可能不会把旧授权自动继承给新版本。

## 安装到 Applications

```bash
cd LookSize
./scripts/install.sh
```

安装脚本会优先使用 `dist/LookSize.app` 的现有通用版本。修改源码后需要重建并安装时：

```bash
REBUILD=1 ./scripts/install.sh
```

如重建时只需要当前机器架构：

```bash
REBUILD=1 UNIVERSAL=0 ./scripts/install.sh
```

安装完成后应用位于：

```text
/Applications/LookSize.app
```

## 使用

1. 启动 LookSize，菜单栏出现尺子图标。
2. 确认菜单显示“辅助功能权限：已授权”。
3. 确认菜单显示“Finder 自动化权限：已授权”。
4. 在 Finder 中单选图片或视频。
5. 按空格打开 Quick Look。

## 命令行验证媒体元数据

构建后可直接检查文件，不依赖辅助功能权限：

```bash
./dist/bin/looksize-inspect /path/to/image.jpg
./dist/bin/looksize-inspect /path/to/video.mov
./dist/bin/looksize-inspect --quicklook-window
```

输出示例：

```text
video.mov · 3840×2160 · 29.97 fps
```

## 可选：安装 ffprobe

LookSize 不强制依赖 FFmpeg。没有 `ffprobe` 时会自动使用 AVFoundation。

```bash
brew install ffmpeg
```

自动检查路径：

```text
/opt/homebrew/bin/ffprobe
/usr/local/bin/ffprobe
/usr/bin/ffprobe
```

也可以指定：

```bash
export LOOKSIZE_FFPROBE=/custom/path/ffprobe
```

注意：从 Finder 启动 App 时不会继承终端临时环境变量，正式使用建议安装到标准 Homebrew 路径。

## 稳定签名与授权继承

构建脚本默认使用临时签名：

```bash
./scripts/build-app.sh
```

临时签名的指定要求（Designated Requirement）通常绑定当前二进制哈希，替换更新后可能需要重新授权。若有固定的 Apple Development 或 Developer ID 证书，可让各版本使用同一签名身份：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
UNIVERSAL=1 ./scripts/build-app.sh
```

面向其他用户长期分发时，彻底稳定升级身份仍建议使用同一 Developer ID 签名并完成 Apple 公证；自动检测只能识别授权失效并引导修复，不能绕过 macOS 的用户确认或替用户授予权限。

## 测试

只安装 Xcode Command Line Tools 时可执行安装包验证：

```bash
cd LookSize
bash -n scripts/*.sh
./scripts/build-dmg.sh
hdiutil verify dist/LookSize-*.dmg
(cd dist && shasum -a 256 -c LookSize-*.dmg.sha256)
```

运行 Swift Testing 单元测试：

```bash
swift test
```

如果本机 `xcode-select` 指向的旧版 Command Line Tools 不包含 Swift Testing，再切换到完整 Xcode：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

手动验收：

1. 菜单栏显示“辅助功能权限：已授权”和“Finder 自动化权限：已授权”。
2. 关闭任一权限后，菜单状态应在约 2 秒内自动更新，尺子图标变为橙色；“授权诊断与修复…”应显示对应状态和当前 App 路径。
3. Finder 单选 JPG/PNG/HEIC，按空格后只补充分辨率，不重复文件名。
4. Finder 单选 MOV/MP4，按空格后只补充分辨率和帧率。
5. 标题栏空间足够时，悬浮信息应紧跟系统文件名右侧且无背景、边框或阴影；空间不足时显示在预览内容左上角。
6. 关闭 Quick Look 或切换到其他应用，悬浮信息应立即隐藏且不闪回。
7. 如果标题没有出现，保持 Quick Look 打开并运行：

```bash
./dist/bin/looksize-inspect --quicklook-window
```

## 卸载

```bash
./scripts/uninstall.sh
```

辅助功能授权记录需要在系统设置中手动删除。

## 已知限制

- 这是锚定在 Quick Look 系统文件名右侧的无交互透明文字层，不是真正修改 Quick Look 标题。
- 多选文件后在 Quick Look 内切换时，优先根据 Quick Look 窗口标题匹配 Finder 选择；单选文件最稳定。
- 没有 `ffprobe` 时，视频帧率来自 AVFoundation 的 `nominalFrameRate`，可变帧率文件只代表轨道标称值。
- Apple Silicon 已通过 arm64 交叉编译，但尚未在 M 系列 Mac 上完成 Quick Look 实机交互验收。
- 免费构建没有 Developer ID 和 Apple 公证，从网络下载后首次启动需要用户在“隐私与安全性”中手动确认；要消除此提示只能加入付费 Apple Developer Program 后进行 Developer ID 签名和公证。
- 默认临时签名构建在二进制更新后，macOS 可能要求重新授予辅助功能和 Finder 自动化权限。建议固定安装到 `/Applications/LookSize.app`；正式分发使用固定 Developer ID 身份。

## 工程结构

```text
Sources/LookSizeCore     元数据、Finder Accessibility、Quick Look 窗口检测
Sources/LookSizeApp      菜单栏 App、监控调度、标题悬浮层
Sources/LookSizeInspect  命令行元数据检查器
Tests                    格式化单元测试
scripts                  构建、安装、卸载脚本
```

## 许可与参考

项目使用 MIT License。Finder 文件识别和媒体元数据提取思路参考并改编自 FinderHover，详见 `THIRD_PARTY_NOTICES.md`。
