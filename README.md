# LookSize

LookSize 是一个原生 macOS 菜单栏工具。在 Finder 中按空格打开 Quick Look 时，系统继续显示原文件名，LookSize 在文件名右侧补充媒体信息：

```text
4032×3024
3840×2160 · 59.94 fps
```

它采用视觉悬浮层，不修改 Finder、Quick Look、媒体文件或系统进程。

## 当前状态

- 版本：0.1.5
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

首次启动后需要两项授权：

```text
系统设置 → 隐私与安全性 → 辅助功能 → LookSize
系统设置 → 隐私与安全性 → 自动化 → LookSize → Finder
```

首次读取 Finder 选择时，系统会询问“LookSize 想控制 Finder”，请选择“允许”。LookSize 只读取当前选中文件路径，不执行改名、移动、删除或写入操作。

授权后如果没有立即生效，退出并重新启动 LookSize。

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
3. 允许 LookSize 自动化控制 Finder。
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

## 测试

```bash
cd LookSize
swift test
bash -n scripts/*.sh
```

手动验收：

1. 菜单栏显示“辅助功能权限：已授权”。
2. Finder 单选 JPG/PNG/HEIC，按空格后只补充分辨率，不重复文件名。
3. Finder 单选 MOV/MP4，按空格后只补充分辨率和帧率。
4. 标题栏空间足够时，悬浮信息应紧跟系统文件名右侧且无背景、边框或阴影；空间不足时显示在预览内容左上角。
5. 关闭 Quick Look 或切换到其他应用，悬浮信息应立即隐藏且不闪回。
6. 如果标题没有出现，保持 Quick Look 打开并运行：

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
- 重建并重新签名 App 后，macOS 可能要求重新授予辅助功能和 Finder 自动化权限。建议固定安装到 `/Applications/LookSize.app`。

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
