# MoonBit 十六进制编辑器

基于 MoonBit 的终端十六进制编辑器与二进制文件分析工具，支持交互式 TUI 界面、16+ 种文件格式解析、搜索与编辑功能。支持 Windows、Linux。

## 功能特性

### 交互式 TUI 界面
- 经典十六进制显示：偏移量列、每行16字节、右侧ASCII字符栏
- 导航：方向键滚动（`↑↓` 逐行、`←→` 翻页）、Home/End跳转、Goto定位 / 书签跳转（`g #N`）
- 搜索：`/` 十六进制模式搜索、`f` ASCII文本搜索、`n`/`N` 上下匹配
- 高亮：当前匹配绿色、其它匹配黄色、编辑光标反色
- 编辑模式：十六进制/ASCII输入、插入、删除、撤销/重做(`Ctrl+Z`/`Ctrl+Y`)带深度显示、保存(`Ctrl+X`)
- 结构视图：解析文件内部结构，支持滚动浏览
- 书签：21 个槽位（0-20），弹出列表自动滚动，`Ctrl+B` 设置，`#N` 跳转
- 签名扫描：`w` 键，20 种格式，每格式独立验证，置信度过滤，结果缓存
  - **图像:** JPEG、PNG、GIF、BMP
  - **压缩/归档:** ZIP、RAR、7z、GZip、Zlib、BZip2
  - **可执行:** PE（exe/dll）、ELF
  - **文档:** PDF、XML
  - **加密:** OpenSSL、PEM、LUKS、GPG
  - **音频:** WAV
  - **数据库:** SQLite3
- 扫描缓存：`w`/`s`/`h` 重新打开时保持上次位置，编辑后自动清除
- 熵分析：`h` 键，256 字节块，香农熵色彩柱状图
- 字符串提取：`s` 键，可打印 ASCII 序列（>=4 字节），支持缓存、跳转高亮
- 提取与检测：`x` 键提取选中段，尾部数据自动告警
- mmap 加载：内存映射文件 I/O 加速大文件打开（失败时自动回退常规读取）
- 显示：自适应终端高度，双行帮助栏

### CLI 命令
```
moon run --target native cmd/main -- view [-b 8|16] <文件>  快速十六进制查看
moon run --target native cmd/main -- info <文件>      文件信息与类型识别
moon run --target native cmd/main -- search [-x|-a] <f> <p>  搜索（hex/文本）
moon run --target native cmd/main -- struct <文件>    结构解析
moon run --target native cmd/main -- strings <文件>   字符串提取
moon run --target native cmd/main -- entropy <文件>   熵分析
moon run --target native cmd/main -- scan <文件>      签名扫描
```

### 文件结构解析（16种格式）

| 类别 | 格式 |
|------|------|
| 图像 | JPEG、PNG、GIF、BMP |
| 音频 | WAV、FLAC、MP3、OGG |
| 视频 | AVI、MP4、WebM/MKV |
| 压缩 | ZIP、RAR、TAR、ZLIB |
| 可执行 | PE（exe/dll）、ELF |

解析详情：图像/视频尺寸、音频采样率/声道、压缩方法与文件名、可执行文件段表、ZIP/RAR加密检测。

## 构建与使用

```bash
# 构建
moon build --target native

# 运行测试
moon test

# 启动 TUI
moon run --target native cmd/main -- 文件.bin
moon run --target native cmd/main                  # 空启动
```

### TUI 快捷键

| 普通模式 | 功能 | 编辑模式 | 功能 |
|----------|------|----------|------|
| `q` | 退出 | `Esc` | 退出编辑 |
| `↑↓` | 逐行滚动 | `↑↓←→` | 移动光标 |
| `←→` | 翻页 | `0-9 a-f` | 十六进制输入 |
| `Home/End` | 首/尾 | `Tab` | 切换Hex/ASCII模式 |
| `g` | 跳转 / #N 书签 | `i` | 插入字节 |
| `/` | 十六进制搜索 | `Del` | 删除字节 |
| `f` | 文本搜索 | `Ctrl+Z` | 撤销 |
| `n` | 下一个匹配 | `Ctrl+Y` | 重做 |
| `p` | 上一个匹配 | `Ctrl+X` | 保存 |
| `e` | 进入编辑 | `Ctrl+B` | 设置书签 |
| `t` | 结构视图 |  |  |
| `b` | 书签列表 | | |
| `w` | 签名扫描 | | |
| `h` | 熵分析 | | |
| `s` | 字符串提取 | | |

结构视图模式：`↑↓←→` 滚动、`t`/`Esc` 返回十六进制视图、`q` 退出。

书签列表：`↑↓` 选择、`Enter` 跳转、`d` 删除、`b`/`Esc` 关闭、`q` 退出、`Ctrl+B` 设置。

签名扫描：`↑↓←→` 导航、`Enter` 跳转、`x` 提取、`w`/`Esc` 关闭，未编辑时结果缓存。

熵分析：`↑↓←→` 导航、`Enter` 跳转、`h`/`Esc` 关闭。

字符串提取：`↑↓←→` 导航、`Enter` 跳转+高亮、`s`/`Esc` 关闭。

### 平台说明

| 平台 | 详情 |
|------|------|
| Windows | conio + ENABLE_VIRTUAL_TERMINAL_PROCESSING，alternate screen buffer，`CreateFileMapping` mmap |
| Linux | termios 持久 raw mode，信号安全恢复，alt screen，直接 `write()`，`mmap`（系统调用） |

## 项目结构

```
hex_editor/
├── hex_editor.mbt                # HexBuffer 数据模型、文件 I/O、编辑基本操作
├── hex_view.mbt                 # 十六进制格式化、尺寸显示
├── hex_search.mbt               # Boyer-Moore-Horspool 搜索（find_all、parse_hex）
├── hex_struct.mbt               # 16+ 种文件格式解析器（JPEG/PNG/ZIP/PE/ELF...）
├── hex_scan.mbt                 # 签名扫描（20 种格式）、熵分析、字符串提取
├── hex_edit.mbt                 # 编辑辅助占位
├── hex_editor_test.mbt          # 单元测试
├── cmd/main/
│   ├── main.mbt                 # CLI 入口（view/info/struct/strings/entropy/scan）
│   ├── helpers.mbt              # CLI 参数解析、文件加载、类型检测
│   ├── helpers_native.mbt       # Native 平台辅助函数（hex/ASCII 转换）
│   ├── tui.mbt                  # TUI 主循环、FFI 声明、mmap 加载
│   ├── tui_key.mbt              # 所有模式的按键分发、TuiState 结构体
│   ├── tui_bookmark.mbt         # 书签功能（21 槽位）、设置/跳转/删除
│   ├── tui_draw.mbt             # 屏幕渲染（hex dump、弹窗、状态栏/帮助栏）
│   ├── tui_edit.mbt             # TUI 编辑模式、基于 UndoOp 的撤销/重做
│   └── tui_stub.c               # C 终端桩（raw mode、alt screen、mmap I/O）
```

## 依赖

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — 文件I/O与系统API
- MoonBit 0.1.20260529+

## 许可证

Apache-2.0
