# MoonBit Hex Editor — 初赛技术说明文档

## 一、参赛任务完成情况

本项目使用 MoonBit 语言从零构建了一个功能完整的终端十六进制编辑器与二进制文件分析工具，全部任务指标均已达成。

### 1.1 核心功能完成清单

| 模块 | 功能项 | 状态 |
|------|--------|------|
| 数据模型 | Gap Buffer 数据结构，支持 O(1) 插入/删除 | ✓ |
| 十六进制显示 | 偏移列 + 16字节/行 + ASCII 字符栏，自适应终端尺寸 | ✓ |
| 交互式 TUI | 完整键盘导航（方向键/Home/End/Goto）、状态栏、帮助栏 | ✓ |
| 编辑系统 | Hex/ASCII 双模式输入、插入/覆写切换、撤销/重做（Ctrl+Z/R） | ✓ |
| 选区操作 | 可视选区（Ctrl+Y）、复制（Ctrl+N）、粘贴（Ctrl+L），复合撤销 | ✓ |
| 保存与恢复 | 文件保存（Ctrl+X）、书签持久化到 `~/.hexedit/` | ✓ |
| 搜索 — 精确 | Boyer-Moore-Horspool 算法，hex 和 ASCII 两种模式 | ✓ |
| 搜索 — 通配符 | `??` 任意字节、`*` 任意长度、`*N` 跳过 N 字节，支持转义 | ✓ |
| 结构解析 | 20 种文件格式解析器（图像/音频/视频/归档/可执行） | ✓ |
| 签名扫描 | Aho-Corasick 多模式匹配 + 14 格式验证器 + 提取隐写文件 + 置信度过滤 | ✓ |
| 熵分析 | 256 字节块香农熵，颜色柱状图可视化 | ✓ |
| 字符串提取 | 可打印 ASCII 序列提取（≥4 字节），跳转高亮 | ✓ |
| 编解码 | Base64 / URL / Unicode / Hex 编解码，交互式弹窗实时预览 | ✓ |
| 多文件支持 | Tab 文件列表弹窗，独立切换/关闭多个文件 | ✓ |
| 文件浏览器 | 目录导航、文件打开（`o` 键），UTF-8 中文文件名支持 | ✓ |
| 导出功能 | 结构信息导出 JSON、字符串导出文本 | ✓ |
| 跨平台 | Windows（conio + ENABLE_VIRTUAL_TERMINAL）+ Linux（termios） | ✓ |
| 双目标编译 | Native（TUI + CLI） + Wasm-GC（CLI only），同一代码库 | ✓ |
| mmap 加速 | 内存映射文件加载，自动回退标准 I/O | ✓ |
| 一键搭建 | setup.sh（Linux）+ setup.ps1（Windows），自动安装 GCC/MoonBit/依赖 | ✓ |

### 1.2 项目规模统计

| 指标 | 数值 |
|------|------|
| MoonBit 源代码行数 | ~5,800 行（17个 .mbt 文件） |
| C FFI 层代码行数 | ~460 行（tui_stub.c，17 个 FFI 函数） |
| 支持的二进制格式 | 20 种 |
| 测试用例数 | 85 个（全部通过） |
| 支持的操作系统 | Windows 11、Linux |
| 编译目标 | Native（x86_64）+ Wasm-GC |
| 外部依赖 | 仅 moonbitlang/x v0.4.45 |

---

## 二、设计思路

### 2.1 总体架构

项目采用**分层架构**设计，自底向上分为三层：

```
┌─────────────────────────────────────────────────────┐
│  用户界面层（cmd/main/）                              │
│  ├─ TUI 交互 (tui.mbt / tui_draw.mbt / tui_key.mbt) │
│  ├─ 编辑系统 (tui_edit.mbt)                          │
│  ├─ 文件管理 (tui_files.mbt / tui_bookmark.mbt)      │
│  └─ CLI 入口 (main.mbt / helpers.mbt)                │
├─────────────────────────────────────────────────────┤
│  核心库层（hex_editor/）                              │
│  ├─ 数据模型 (hex_editor.mbt)                        │
│  ├─ 搜索引擎 (hex_search.mbt)                        │
│  ├─ 结构解析 (hex_struct.mbt)                        │
│  ├─ 签名扫描 (hex_scan.mbt)                          │
│  ├─ 显示格式 (hex_view.mbt)                          │
│  ├─ 编解码器 (hex_codec.mbt)                         │
│  ├─ 熵分析 (hex_entropy.mbt)                         │
│  └─ 字符串提取 (hex_strings.mbt)                     │
├─────────────────────────────────────────────────────┤
│  平台抽象层                                          │
│  ├─ C FFI (tui_stub.c) — 终端控制 / mmap / 文件系统  │
│  ├─ moonbitlang/x — 文件 I/O / 系统 API              │
│  └─ Wasm-GC 纯 MoonBit (cmd/wasm/)                   │
└─────────────────────────────────────────────────────┘
```

**核心设计原则：**
- **核心库零平台依赖**：底层 `hex_editor` 模块纯 MoonBit 实现，所有算法不依赖任何操作系统特性，可同时用于 Native 和 Wasm-GC 目标
- **界面与逻辑分离**：TUI 和 CLI 共享同一核心库，仅展示层不同
- **增量渲染**：每帧构建完整屏幕字符串后一次性输出，避免逐字节光标移动

### 2.2 数据结构选型

**为什么选择 Gap Buffer？**

十六进制编辑器最核心的数据结构需求是：在任意位置高效插入/删除字节，同时支持快速的随机读取和遍历显示。

| 方案 | 随机访问 | 插入/删除 | 内存开销 |
|------|---------|----------|---------|
| 数组 | O(1) | O(n) | 低 |
| 链表 | O(n) | O(1) | 高 |
| Rope/Piece Table | O(log n) | O(log n) | 中 |
| **Gap Buffer** | **O(1)** | **O(1)** at cursor | **低** |

Gap Buffer 完美匹配编辑器的工作模式：用户通常在一个位置连续编辑（光标处），偶尔移动光标（O(distance) 移动间隙）。间隙大小 = 文件磁盘分配 / 16（最小 256 字节），在空间效率和扩展频率之间取得平衡。

**物理布局**：`[已编辑数据 | 间隙（未使用空间） | 光标后数据]`

关键操作：
- `byte_at(i)` → 逻辑索引转换为物理索引，O(1)
- `insert_byte(pos, b)` → 移动间隙到 pos，写入间隙头部，O(distance + 1)
- `delete_byte(pos)` → 移动间隙到 pos，扩展间隙吞噬该字节，O(distance + 1)
- `save()` → 导出逻辑字节序列写入文件

### 2.3 跨平台策略

项目通过**编译期条件选择**实现平台无关性：

```
 moon.pkg 中声明：
   native → 链接 tui_stub.c，启用 FFI（终端控制、mmap）
   wasm-gc → 纯 MoonBit 实现，仅 CLI 输出
```

C FFI 层（`tui_stub.c`）封装了 Windows 和 Linux 的差异：
- **终端控制**：Windows 使用 `conio.h`（`_kbhit`/`_getch`）+ `ENABLE_VIRTUAL_TERMINAL_PROCESSING`；Linux 使用 `termios` + `select`/`read` + 信号安全恢复
- **内存映射**：Windows 使用 `CreateFileMapping`/`MapViewOfFile`；Linux 使用 `mmap` 系统调用
- **目录操作**：Windows 使用 `FindFirstFileW`/`FindNextFileW`（宽字符 API，支持中文文件名）；Linux 使用 `opendir`/`readdir`

---

## 三、实现方案

### 3.1 搜索子系统：三级策略引擎

搜索模块采用**三级策略自适应调度**：

```
输入模式
  ├─ 纯精确字节序列 → Boyer-Moore-Horspool (O(n/m) 平均)
  ├─ 含 ?? 通配符（无 *） → Shift-Or 位并行 (O(n)，最多 62 字节)
  └─ 含 * 多通配符 → 贪婪分段匹配 (O(n·segments))
```

**Boyer-Moore-Horspool 实现细节：**
- 构建 256 字节坏字符跳跃表
- 失配时跳跃 `skip[text[i + m - 1]]` 个位置
- 匹配结果上限 2000 个，防止大文件搜索卡顿

**Shift-Or 位并行实现细节：**
- 每个字节值对应一个 64 位掩码（bit i = 0 表示该字节匹配模式第 i 位）
- 状态寄存器初始化为全 1（`~(1 << m)`
- 逐字节更新：`state = (state << 1) | mask[byte]`
- 接受位清零时记录匹配
- 超过 62 字节的模式自动回退到滑动窗口

**通配符语法完整支持：**
- Hex 模式：`??` 任意单字节、`*` 任意长度、`*N` 精确跳过 N 字节（如 `FF *3 0D 0A`）
- ASCII 模式：`?` 任意单字符、`*` 任意长度、`*N` 精确跳过 N 字符、`\` 转义文字量

### 3.2 签名扫描：Aho-Corasick + 置信度验证

十四进制文件签名检测分两阶段进行：

**阶段一：Aho-Corasick 多模式匹配**

```
构建 Trie（17 个魔数字节模式）
  → BFS 构建失败链接
  → 补全所有转移边（256 × N 个节点）
  → 单趟扫描文件，O(n + m + z)
```

17 个基础模式对应：JPEG (FFD8)、PNG (89504E47)、GIF (47494638)、BMP (424D)、RIFF (52494646)、ZIP (504B0304/504B0506/504B0102)、RAR (526172211A07)、7z (377ABCAF271C)、GZip (1F8B08)、Zlib (789C/78DA/7801)、BZip2 (425A68)、PE (4D5A)、ELF (7F454C46)、TAR（位置约束匹配）

**阶段二：逐格式结构验证（14 个验证器）**

每个验证器对候选偏移进行深度检查：

| 格式 | 验证逻辑 |
|------|---------|
| JPEG | 检查 0xFFD8 + 后续标记字节有效性（0xE0-0xEF/0xFE/0xDB/0xC0-0xC4） |
| PNG | 验证 8 字节签名 + IHDR 块（含尺寸字段合理性检查） |
| ZIP | 验证版本号 / 标志 / 压缩方法字段约束 |
| PE | 检查 e_lfanew 指向有效 "PE\0\0" 签名 |
| TAR | 确认 ustar 魔数出现在 (offset - 257) % 512 == 0 的位置 |
| GIF/BMP/WAV/ELF | 结构完整性验证 |

**置信度评分**：
- 1 = 仅魔数匹配（低置信度）
- 2 = 结构验证通过（中置信度）
- 3 = 检测到尾部标记/结束符（高置信度）

**误报过滤**：抑制容器格式内部低置信度匹配（如 JPEG 内的 Zlib 块）

### 3.3 结构解析：20 格式递归下降解析器

每种格式实现为独立的 `parse_*` 函数，采用**格式原生结构递归下降**方式：

```
parse_structure(data)
  → 读取前 4 字节魔数
  → 按优先级匹配：JPEG > PNG > PE > ZIP > GIF > BMP > RAR > TAR > ZLIB > WAV > ...
  → 调度到对应 parse_* 函数
  → 返回 StructField 树（含 offset/size/name/value/description/children）
```

**关键解析器实现要点：**

- **JPEG**：扫描 0xFF 标记流水线（SOF0/1/2 提取尺寸、DHT/DQT 哈夫曼/量化表、SOS 扫描数据、APP0-15/COM 元数据、RST0-7 重启间隔）
- **PNG**：逐块解析 IHDR（宽/高/位深/颜色类型）、PLTE、IDAT、IEND、tEXt、tIME、pHYs
- **PE**：DOS 头 → e_lfanew → COFF 头（机器类型/节数）→ 可选头（PE32/PE32+、入口点、映像基址）→ 节表遍历
- **ELF**：根据 class（32/64 位）和 endianness（大/小端）动态调整字段宽度，读取程序头/节头偏移
- **MP4/WebM**：Box/EBML 容器层次扫描，含元素名称查找表
- **ZIP**：本地文件头 → 中央目录 → EOCD 三级扫描，加密检测
- **WAV**：RIFF 块结构（fmt 采样率/声道/位深、data 块大小）
- **FLAC/OGG/MP3**：流格式页/帧/ID3v2 标签解析

### 3.4 编辑系统：复合撤销设计

撤销/重做基于**逆操作模型**，支持 5 种操作类型：

```
UndoOp {
  kind: 0=Modify | 1=Insert | 2=Delete | 3=PasteOverwrite | 4=PasteInsert
  offset: Int
  old_byte: Byte          // Modify/Delete 的恢复数据
  old_bytes: Array[Byte]  // Paste 的批量恢复数据
  count: Int              // Paste 影响的字节数
}
```

**核心设计决策**：
- 每次操作返回其逆操作 → 撤销栈和重做栈互为镜像
- 粘贴操作产生单个复合 `UndoOp`（而非 N 个独立操作） → 一次 Ctrl+Z 即可撤销整个粘贴
- 选区复制时，先覆盖粘贴（kind 3），再根据情况插入（kind 4），保证数据一致性
- Esc 退出编辑时自动调用 `revert_all_edits()` 丢弃所有未保存修改

### 3.5 熵分析：查找表优化

针对 256 字节块的香农熵计算，采用**预计算查找表**消除对数运算：

```
H = -Σ (count_k / 256) × log2(count_k / 256)   [完整块]

预计算: table[k] = -(k/256) × log₂(k/256)   for k ∈ [0, 256]
完整块熵 = Σ table[freq[b]]                    [纯查表，零次 log2]

非完整块（末尾 < 256 字节）:
  log₂(x) = log₂(m × 2^e) = e + log₂(m)       [m ∈ [1, 2)]
  ln(m) 使用 6 项 Horner 形式泰勒级数展开
  log₂(m) = ln(m) / ln(2)
```

对典型 1.8MB PNG 文件：~7200 个完整块（纯查表）+ 1 个部分块（6 次浮点运算），log2 调用从 ~7200 次降至 1 次。

### 3.6 终端渲染：多区域位图高亮

全屏渲染由 `draw_screen()` 统一完成，一次 `raw_print()` 输出：

```
1. ESC[H  （光标归位）
2. 计算可见范围：offset .. offset + rows × 16
3. 构建两个高亮度位图（FixedArray[Bool] × 可见范围）:
   - highlight_bitmap: 所有搜索匹配位置
   - match_bitmap:     当前活动匹配位置
4. 逐行渲染（每行 16 字节）:
   - 偏移列（蓝色 / 暗蓝色）
   - 16 个十六进制字节（含 ANSI 颜色码）:
     * 反色 = 编辑光标
     * 绿底 = 当前匹配
     * 黄底 = 其他匹配
     * 紫底 = 选区
   - ASCII 字符栏
5. 状态栏（蓝底，偏移量 + 行号 + 状态信息）
6. 帮助栏 × 2（白字黑底快捷键提示，按终端宽度裁剪）
7. 弹窗覆盖层（扫描/熵/字符串/编解码/书签/文件列表/浏览器）
```

位图使用 `FixedArray[Bool]` 而非 `Array`，保证 **O(1) 栈分配**（无堆分配），适合每帧重新构建。

### 3.7 Wasm-GC 目标

Wasm-GC 版本（`cmd/wasm/main.mbt`）复用全部核心库，去掉 TUI 和 FFI 依赖：

- 支持 view / struct / scan / strings / entropy / search / encode / decode / help 共 9 个 CLI 命令
- 使用 MoonBit 的 `println` 直接输出，无终端控制依赖
- 同一套 20 种格式解析器和搜索算法，零代码重复

---

## 四、测试验证结果

### 4.1 测试总览

```
$ moon test --target native

Total tests: 85, passed: 85, failed: 0.
```

全部 85 个测试用例通过，覆盖核心库全部模块。

### 4.2 测试覆盖矩阵

| 测试类别 | 用例数 | 覆盖模块 | 测试内容 |
|---------|--------|---------|---------|
| HexBuffer 操作 | 12 | hex_editor.mbt | 构造/读/写/插入/删除/导出/往返/容量增长/修改标记 |
| Gap Buffer 机制 | 2 | hex_editor.mbt | 跨位置插入间隙移动、大量插入触发扩容 |
| 显示格式化 | 6 | hex_view.mbt | 字节 hex/ASCII 格式化、偏移格式化、尺寸显示、hex dump |
| 编解码 | 16 | hex_codec.mbt | Base64/URL/Unicode/Hex 各格式编解码往返测试、已知向量验证、非法输入边界测试 |
| 搜索算法 | 11 | hex_search.mbt | BMH 精确匹配、hex 模式解析、`??` 通配符、`*` 多通配符、`*N` 固定跳过、文本模式（含 `?`/`*`/`\` 转义） |
| 格式扫描与解析 | 22 | hex_scan.mbt + hex_struct.mbt | 14 种格式签名扫描 + 20 种格式结构解析（使用 testfile/ 真实文件） |
| 隐写与混合 | 2 | hex_scan.mbt | JPEG 内嵌数据检测（hidden.jpg）、多文件合并检测（mergejp.jpg） |
| 熵与字符串 | 2 | hex_entropy.mbt + hex_strings.mbt | 均匀/离散熵精度验证、ASCII 字符串提取 |
| 边界与安全性 | 6 | 全部模块 | 空输入安全（b"" 所有 7 模块）、JSON 导出、Buffer info |

### 4.3 测试数据

`testfile/` 目录包含 24 个涵盖所有支持格式的真实二进制文件：

- 图像：test.png, test.jpg, test.gif, test.bmp
- 音频：test.wav, test.flac, test.ogg, test.mp3
- 视频：test.avi, test.mp4, test.webm
- 归档：test.zip, test.rar, test.tar, test.gz, test.bz2, test.zlib, test.7z
- 可执行：test.exe (PE), test.elf
- 特殊：hidden.jpg（含嵌入数据）、mergejp.jpg（双文件合并）、test.bin（通用二进制）、test.txt（纯文本）

### 4.4 跨平台验证

| 平台 | 编译 | 测试 (85 cases) | TUI 交互 | CLI 命令 | Wasm-GC |
|------|------|----------------|---------|---------|---------|
| Windows 11 | ✓ | ✓ 全部通过 | ✓ | ✓ | ✓ |
| Linux | ✓ | ✓ 全部通过 | ✓ | ✓ | ✓ |

### 4.5 性能特征

| 操作 | 复杂度 | 实测参考（1.8 MB PNG） |
|------|--------|----------------------|
| 文件加载（mmap） | O(n) | < 10ms |
| 结构解析 | O(n) | < 50ms |
| 签名扫描 | O(n + z) | < 30ms |
| 字符串提取 | O(n) | < 20ms |
| 熵分析（256B 块） | O(n) | < 15ms（查找表优化） |
| 搜索（BMH 精确） | O(n/m) avg | < 5ms |
| 插入/删除（光标处） | O(1) | < 1μs |
| 屏幕渲染（70 行） | O(rows × 16) | < 5ms |

---

## 五、核心创新点

### 5.1 一门新语言的全栈实践验证

本项目是 **MoonBit 语言在系统编程领域最全面的实践案例之一**，在一个统一代码库中验证了：

- **C FFI 互操作**：17 个 extern 函数，封装 Windows conio / Linux termios，验证了 MoonBit 与 C 生态的无缝集成能力
- **裸终端控制**：不依赖 ncurses 等第三方库，纯 ANSI 转义序列 + 平台 API，证明 MoonBit 可以实现底层系统编程
- **跨平台编译**：同一套代码编译到 x86_64 Native 和 Wasm-GC 两个目标，零修改共享核心库
- **算法表达力**：Aho-Corasick 自动机、Shift-Or 位并行、Boyer-Moore-Horspool 等经典算法均在 MoonBit 中自然表达
- **大型工程组织**：17 个源文件、约 5800 行代码、85 个测试用例，证明 MoonBit 具备中型项目的工程化能力

### 5.2 搜索算法的三级自适应调度

不同于传统 hex 编辑器单一搜索策略，本系统根据输入模式特征动态选择最优算法：

- **纯精确匹配** → Boyer-Moore-Horspool（O(n/m) 平均，适用于大文件快速扫描）
- **含 `??` 通配符** → Shift-Or 位并行（O(n)，单寄存器状态机，避免重复扫描）
- **含 `*` 多通配符** → 贪婪分段匹配（将模式按 `*` 分割，逐段定位后合并结果）

三种策略在 `find_hex_pattern()` 函数内自动切换，对用户透明。支持 `*N` 精确控制跳过字节数，为 CTF 场景中的结构化搜索提供了灵活的表达能力。

### 5.3 复合撤销系统

编辑器的撤销/重做采用**逆操作模型**，每个操作立即计算并存储其逆操作：

- 撤销时执行逆操作，并将原操作推入重做栈
- 重做时再次执行逆操作（回到原状态），循环往复
- 粘贴操作产生**单个复合 UndoOp**（而非拆分为 N 个独立操作），保证 Ctrl+Z 一次性撤销整个粘贴
- 5 种操作类型覆盖所有编辑场景：修改/插入/删除/覆盖粘贴/插入粘贴

### 5.4 熵分析的零对数查表优化

针对 256 字节块的香农熵计算，预计算 `-p × log₂(p)` 的 257 个离散值到查找表。完整块仅需累加 256 次查表结果，**完全消除对数运算**。仅文件末尾不足 256 字节的部分块需要 6 项 Horner 形式泰勒级数计算 `log₂`。对于 MB 级文件，对数调用次数从数千次降至 ≤ 1 次。

### 5.5 集成式安全分析工作流

编辑器不仅是查看/编辑工具，更提供**一站式二进制分析工作流**：

1. `w` 签名扫描 → 自动检测文件中嵌入的所有已知格式（隐写分析）
2. `s` 字符串提取 → 提取可打印 ASCII 序列
3. `h` 熵分析 → 通过信息熵分布识别加密/压缩区域
4. `t` 结构解析 → 深入查看 20 种格式的内部结构
5. `c` 编解码 → 交互式 Base64/URL/Unicode/Hex 转换
6. `x` 数据提取 → 导出检测到的嵌入文件
7. `e` 导出 → 结构信息输出 JSON、字符串输出文本

所有分析结果带缓存机制：在编辑操作前，重复打开扫描/字符串/熵视图保持上次位置和结果。

### 5.6 跨平台 UTF-8 文件名支持

文件浏览器和书签系统通过 FFI 调用 Windows Wide API（`FindFirstFileW`/`GetCurrentDirectoryW`）和手动 UTF-8 编解码器（1-4 字节序列），实现中文文件名的正确显示和操作。Linux 端通过原生 UTF-8 路径支持，`realpath` 确保书签持久化的路径一致性。

### 5.7 一键跨平台搭建

`setup.sh` 和 `setup.ps1` 自动检测并安装 GCC、MoonBit 工具链、项目依赖，执行构建和测试。Windows 脚本支持 winget/scoop/choco 三种包管理器的自动降级安装，Linux 脚本支持 apt/yum/pacman/brew 四种包管理器。两脚本均包含安装后验证和清晰的错误提示。

---

## 附录：项目结构速览

```
hex_editor/
├── hex_editor.mbt           # Gap Buffer 数据模型、文件 I/O、编辑原语
├── hex_view.mbt             # 十六进制格式化、尺寸显示
├── hex_search.mbt           # BMH / Shift-Or / 贪婪分段搜索
├── hex_struct.mbt           # 20 种文件格式递归下降解析器
├── hex_scan.mbt             # Aho-Corasick 签名扫描 + 14 格式验证
├── hex_strings.mbt          # 可打印 ASCII 字符串提取
├── hex_entropy.mbt          # 香农熵分析（查找表优化）
├── hex_codec.mbt            # Base64 / URL / Unicode / Hex 编解码
├── hex_editor_test.mbt      # 85 个测试用例
├── cmd/main/
│   ├── main.mbt             # CLI 入口（14 个子命令）
│   ├── tui.mbt              # TUI 主循环、FFI 声明、mmap 加载
│   ├── tui_draw.mbt         # 全屏渲染（hex dump + 8 个弹窗）
│   ├── tui_key.mbt          # 按键分发（全部模式的事件处理器）
│   ├── tui_edit.mbt         # 编辑模式、撤销/重做系统
│   ├── tui_files.mbt        # 文件浏览器、多文件管理、书签持久化
│   ├── tui_bookmark.mbt     # 书签弹窗（21 槽位）
│   └── tui_stub.c           # C FFI 桩（终端 / mmap / 目录 / UTF-8）
├── cmd/wasm/main.mbt        # Wasm-GC CLI（轻量版，无 TUI）
├── testfile/                # 24 个测试文件（全部支持格式）
├── setup.sh / setup.ps1     # 一键搭建脚本
├── README.md / README_CN.md # 中英文文档
└── moon.mod / moon.pkg      # 模块配置
```
