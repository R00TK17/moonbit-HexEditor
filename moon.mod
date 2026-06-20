// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "R00TK17/hex_editor"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/R00TK17/moonbit-HexEditor"

license = "Apache-2.0"

keywords = ["hex", "editor", "binary", "tui", "parser", "forensics", "entropy", "steganography"]

description = "Terminal hex editor & binary analysis toolkit: 20 format parsers, wildcard search, entropy analysis, steganography detection, Base64/URL/Unicode/Hex codecs. Cross-platform (Windows/Linux), dual-target (Native + Wasm-GC)."

import {
  "moonbitlang/x@0.4.45",
}
