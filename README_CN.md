[English](README.md) | **中文**

# MoonBit 十六进制编辑器

基于 MoonBit 的终端十六进制编辑器与二进制文件分析工具，支持交互式 TUI 界面、20 种文件格式解析、通配符搜索与完整编辑功能。支持 Windows、Linux，同时编译为 Native 和 Wasm-GC 目标。

> **项目目标**
>
> 使用 MoonBit 从零构建一个功能丰富的十六进制编辑器，覆盖二进制查看、编辑、搜索、多格式解析、隐写检测、编解码等场景。
>
> **选题意义**：十六进制编辑器处于系统编程、二进制分析与交互 UI 的交汇处，是检验新语言实践能力的理想领域。本项目证明 MoonBit 能够在一个统一代码库中实现 C FFI 互操作、裸终端控制、跨平台适配、算法优化、多目标编译（Native + Wasm-GC）。
>
> **使用场景**：二进制结构分析、CTF 隐写挑战、安全取证、通用 hex 编辑。
>
> **技术亮点**：Gap Buffer O(1) 编辑、Aho-Corasick 多模式扫描、Shift-Or 位并行通配符搜索、香农熵查找表优化、20 种文件格式解析器、书签持久化、复合撤销系统、一套代码双目标编译。

## 环境要求

| 工具 | 版本 | 用途 |
|------|------|------|
| [MoonBit](https://www.moonbitlang.com/download/) | 0.1.20260529+ | 编译器与构建工具 |
| GCC | 任意近期版本 | C FFI 编译 |
| Git | 任意 | 克隆仓库 |

## 快速开始

```bash
git clone https://github.com/R00TK17/moonbit-HexEditor.git
cd moonbit-HexEditor

# 一键搭建（自动安装 MoonBit、构建、测试）
# Linux/macOS:
chmod +x setup.sh && ./setup.sh
# Windows PowerShell:
.\setup.ps1

# 或手动操作:
moon update       				   # 安装依赖
moon build --target native         # 构建
moon test --target native          # 85 个测试
moon run --target native cmd/main -- testfile/test.png  # 启动 TUI
```

## 功能特性

### 交互式 TUI 界面
- 经典十六进制显示：偏移量列、每行16字节、右侧ASCII字符栏
- 导航：方向键滚动（`↑↓` 逐行、`←→` 翻页）、Home/End跳转、Goto定位 / 书签跳转（`g #N`）
- 搜索：`/` 十六进制模式搜索、`f` ASCII文本搜索、`n`/`N` 上下匹配
  - Hex 通配符：`??` 任意字节、`*` 任意长度、`*N` 跳过 N 字节（如 `FF ?? 00`、`89 *3 0D 0A`）
  - 文本通配符：`?` 任意字符、`*` 任意长度、`*N` 跳过 N 字符、`\` 转义（如 `He*ld`、`\?`）
- 高亮：当前匹配绿色、其它匹配黄色、编辑光标反色
- 编辑模式：十六进制/ASCII输入、`Ins` 切换插入/覆写、删除、撤销/重做(`Ctrl+Z`/`Ctrl+R`)、保存(`Ctrl+X`)
  - 选区复制粘贴：`Ctrl+Y` 开始选区、`Ctrl+N` 复制、`Ctrl+L` 粘贴（复合撤销）
  - Gap Buffer：光标处插入/删除 O(1)，间隙 = 文件占用空间 / 16
- 结构视图：解析文件内部结构，支持滚动浏览
- 书签：21 个槽位（0-20），弹出列表自动滚动，`Ctrl+B` 设置，`#N` 跳转，**持久化**（自动保存/加载到 `~/.hexedit/`）
- 签名扫描：`w` 键，14 种格式，每格式独立验证，置信度过滤，结果缓存
  - **图像:** JPEG、PNG、GIF、BMP
  - **压缩/归档:** ZIP、RAR、7z、GZip、Zlib、BZip2、TAR
  - **可执行:** PE（exe/dll）、ELF
  - **音频:** WAV
- 扫描缓存：`w`/`s`/`h` 重新打开时保持上次位置，编辑后自动清除
- 熵分析：`h` 键，256 字节块，香农熵色彩柱状图
- 字符串提取：`s` 键，可打印 ASCII 序列（>=4 字节），支持缓存、跳转高亮
- 提取与检测：`x` 键提取选中段，尾部数据自动告警
- 导出：`e` 键在结构/字符串视图 — 结构为 JSON，字符串为纯文本
- 编解码弹窗：`c` 键，交互式 Base64/URL/Unicode/Hex 编解码，实时预览
- 多文件支持：同时打开多个文件，`Tab` 文件列表弹窗，独立切换/关闭
- 文件浏览器：`o` 键打开目录浏览，`Enter` 打开/进入，`o` 输入路径，支持中文文件名
- 书签持久化：书签 + 滚动位置自动保存到 `~/.hexedit/`，下次打开自动恢复
- UTF-8 支持：中文文件名正确显示（Windows Wide API + UTF-8 控制台）
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
moon run --target native cmd/main -- encode <类型> <文件>   编码 (base64/url/unicode/hex)
moon run --target native cmd/main -- decode <类型> <文件>   解码 (base64/url/unicode/hex)
moon run --target native cmd/main -- base64 <文件>          Base64 编码（别名）
moon run --target native cmd/main -- unbase64 <文件>        Base64 解码（别名）
```

### Wasm-GC CLI（轻量版，无 TUI，无 FFI）
```
moon run --target wasm-gc cmd/wasm -- view <文件>            Hex dump（前 256 字节）
moon run --target wasm-gc cmd/wasm -- struct <文件>           结构解析
moon run --target wasm-gc cmd/wasm -- scan <文件>             签名扫描
moon run --target wasm-gc cmd/wasm -- search <文件> <模式>    搜索
moon run --target wasm-gc cmd/wasm -- strings <文件>          字符串
moon run --target wasm-gc cmd/wasm -- entropy <文件>          熵分析
moon run --target wasm-gc cmd/wasm -- encode <类型> <输入>    编码
moon run --target wasm-gc cmd/wasm -- decode <类型> <输入>    解码
```

### 输出示例

```
$ moon run --target native cmd/main -- struct testfile/test.png
File: testfile/test.png (1.8 MB)

0x00000000  Signature = 89 50 4E 47 0D 0A 1A 0A  -- PNG signature
0x00000008  IHDR = 13 bytes  -- Image Header: 3178x1334, 8bpp
0x00000021  pHYs = 9 bytes  -- Physical dimensions
0x00000530  IDAT = 1048576 bytes  -- Image data block
0x001D0E32  IEND = 0 bytes  -- Image end

$ moon run --target native cmd/main -- scan testfile/hidden.jpg
0x00000000  JPEG image (83.8 KB)
0x0000A41A  Trailing data (82 B)
2 signatures found

$ moon run --target native cmd/main -- encode base64 Hello
SGVsbG8=
```

### 文件结构解析（20种格式）

| 类别 | 格式 |
|------|------|
| 图像 | JPEG、PNG、GIF、BMP |
| 音频 | WAV、FLAC、MP3、OGG |
| 视频 | AVI、MP4、WebM/MKV |
| 压缩 | ZIP、RAR、TAR、ZLIB、GZip、7z、BZip2 |
| 可执行 | PE（exe/dll）、ELF |

解析详情：图像/视频尺寸、音频采样率/声道、压缩方法与文件名、可执行文件段表、ZIP/RAR加密检测。

## 构建与使用

```bash
# 构建
moon build --target native

# 运行测试
moon test --target native

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
| `g` | 跳转 / #N 书签或地址 | `Ins` | 切换插入/覆写 |
| `/` | 十六进制搜索 | `Del` | 删除字节 |
| `f` | 文本搜索 | `Ctrl+Z` | 撤销 |
| `n` | 下一个匹配 | `Ctrl+R` | 重做 |
| `p` | 上一个匹配 | `Ctrl+X` | 保存 |
| `e` | 进入编辑 | `Ctrl+Y` | 选区 |
| `t` | 结构视图 | `Ctrl+N` | 复制 |
| `b` | 书签列表 | `Ctrl+L` | 粘贴 |
| `w` | 签名扫描 | `Ctrl+B` | 设置书签 |
| `h` | 熵分析 | | |
| `s` | 字符串提取 | | |
| `c` | 编解码 | | |
| `o` | 文件浏览器 | | |
| `Tab` | 文件列表（多文件） | | |

结构视图模式：`↑↓←→` 滚动、`t`/`Esc` 返回十六进制视图、`q` 退出。

书签列表：`↑↓` 选择、`Enter` 跳转、`d` 删除、`b`/`Esc` 关闭、`q` 退出、`Ctrl+B` 设置。

签名扫描：`↑↓←→` 导航、`Enter` 跳转、`x` 提取、`w`/`Esc` 关闭，未编辑时结果缓存。

熵分析：`↑↓←→` 导航、`Enter` 跳转、`h`/`Esc` 关闭。

字符串提取：`↑↓←→` 导航、`Enter` 跳转+高亮、`s`/`Esc` 关闭。

编解码：`←→` 切换类型（Base64/URL/Unicode/Hex）、`Tab` 切换编码/解码、直接输入文本、`Esc` 关闭。

文件浏览器（`o`）：`↑↓` 导航、`Enter` 打开文件/进入目录、`o` 输入路径、`Esc` 取消。

文件列表（`Tab`）：`↑↓` 选择、`Enter` 切换、`d` 关闭文件、`Tab`/`Esc` 返回。

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
├── hex_search.mbt               # 搜索：BMH 精确、通配符（?? * *N）、文本模式（? * \）
├── hex_struct.mbt               # 20 种文件格式解析器 + JSON 导出
├── hex_scan.mbt                 # 签名扫描（14 种格式）、Aho-Corasick 自动机
├── hex_strings.mbt              # 可打印 ASCII 字符串提取
├── hex_entropy.mbt              # 香农熵分析（256 字节块）
├── hex_codec.mbt                # 编解码：Base64、URL、Unicode、Hex
├── hex_editor_test.mbt          # 85 个单元 + 集成测试
├── cmd/main/
│   ├── main.mbt                 # CLI 入口（view/info/struct/strings/entropy/scan）
│   ├── helpers.mbt              # CLI 参数解析、文件加载、类型检测
│   ├── helpers_native.mbt       # Native 平台辅助函数（hex/ASCII 转换）
│   ├── tui.mbt                  # TUI 主循环、FFI 声明、mmap 加载
│   ├── tui_key.mbt              # 所有模式的按键分发、TuiState 结构体
│   ├── tui_bookmark.mbt         # 书签功能（21 槽位）、设置/跳转/删除
│   ├── tui_files.mbt            # 文件浏览器、多文件管理、书签持久化
│   ├── tui_draw.mbt             # 屏幕渲染（hex dump、弹窗、状态栏/帮助栏）
│   ├── tui_edit.mbt             # TUI 编辑模式、基于 UndoOp 的撤销/重做
│   └── tui_stub.c               # C 桩（终端、mmap、目录列表、UTF-8）
├── cmd/wasm/
│   └── main.mbt                 # Wasm-GC CLI 入口（轻量版，无 FFI）
├── testfile/                    # 24 个测试文件（覆盖所有支持格式）
├── setup.sh / setup.ps1         # 一键搭建脚本
```

## 依赖

- [moonbitlang/x](https://github.com/moonbitlang/x) — 文件I/O与系统API
- MoonBit 0.1.20260529+

## 许可证

Apache-2.0
