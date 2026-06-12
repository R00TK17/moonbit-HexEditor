# MoonBit 十六进制编辑器

基于 MoonBit 的终端十六进制编辑器与二进制文件分析工具，支持交互式 TUI 界面、16+ 种文件格式解析、搜索与编辑功能。支持 Windows、Linux。

## 功能特性

### 交互式 TUI 界面
- 经典十六进制显示：偏移量列、每行16字节、右侧ASCII字符栏
- 导航：方向键滚动（`↑↓` 逐行、`←→` 翻页）、Home/End跳转、Goto定位
- 搜索：`/` 十六进制模式搜索、`f` ASCII文本搜索、`n`/`N` 上下匹配
- 高亮：当前匹配绿色、其它匹配黄色、编辑光标反色
- 编辑模式：十六进制/ASCII输入、插入、删除、撤销/重做(`Ctrl+Z`/`Ctrl+Y`)带深度显示、智能保存提示
- 结构视图：解析文件内部结构，支持滚动浏览
- 显示：自适应终端高度，文件信息启动时展示，状态栏 + 帮助栏

### CLI 命令
```
moon run --target native cmd/main -- view <文件>     快速十六进制查看
moon run --target native cmd/main -- info <文件>     文件信息与类型识别
moon run --target native cmd/main -- search <f> <p>  模式搜索
moon run --target native cmd/main -- struct <文件>   结构解析
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
| `g` | 跳转偏移 | `i` | 插入字节 |
| `/` | 十六进制搜索 | `Del` | 删除字节 |
| `f` | 文本搜索 | `Ctrl+Z` | 撤销 |
| `n/N` | 上/下一个匹配 | `Ctrl+Y` | 重做 |
| `e` | 进入编辑 | `Ctrl+S` | 保存 |
| `t` | 结构视图 | | |

结构视图模式：`↑↓←→` 滚动、`t` 返回十六进制视图、`q` 退出。

### 平台说明

| 平台 | 详情 |
|------|------|
| Windows | conio + ENABLE_VIRTUAL_TERMINAL_PROCESSING，alternate screen buffer |
| Linux | termios 持久 raw mode，信号安全恢复，alt screen，直接 `write()` |

## 项目结构

```
hex_editor/
├── hex_editor.mbt / hex_view.mbt / hex_search.mbt / hex_edit.mbt / hex_struct.mbt
├── hex_editor_test.mbt           # 测试文件
├── cmd/main/
│   ├── main.mbt                  # CLI + TUI 入口
│   ├── helpers.mbt / helpers_native.mbt  # 共享工具函数
│   ├── tui.mbt                   # TUI 主循环与输入
│   ├── tui_draw.mbt              # 屏幕渲染（缓冲、单次刷新）
│   ├── tui_edit.mbt              # 编辑模式、撤销/重做
│   └── tui_stub.c                # C 终端桩代码（raw mode、alt screen、自适应尺寸）
```

## 依赖

- [moonbitlang/x](https://mooncakes.io/packages/moonbitlang/x) — 文件I/O与系统API
- MoonBit 0.1.20260529+

## 许可证

Apache-2.0
