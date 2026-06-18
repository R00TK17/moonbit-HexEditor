// Hex Editor — Entropy Analysis
// Shannon entropy calculation on 256-byte blocks.

///|
pub struct EntropyBlock {
  start : Int
  end : Int
  entropy : Double
} derive(Debug)

///|
/// Scan bytes in 256-byte blocks, compute Shannon entropy per block.
pub fn entropy_scan(bytes : Bytes) -> Array[EntropyBlock] {
  let len = bytes.length(); let block_size = 256
  let results : Array[EntropyBlock] = []; let mut off = 0
  while off < len {
    let end = if off + block_size < len { off + block_size } else { len }
    let counts = FixedArray::make(256, 0)
    for j = off; j < end; j = j + 1 { let idx = bytes[j].to_int(); counts[idx] = counts[idx] + 1 }
    let n = (end - off).to_double(); let mut h = 0.0
    for k = 0; k < 256; k = k + 1 { if counts[k] > 0 { let p = counts[k].to_double() / n; h = h - p * log2(p) } }
    results.push({ start: off, end, entropy: h }); off = end
  }
  results
}

///|
fn log2(x : Double) -> Double {
  if x <= 0.0 || x >= 1.0 { 0.0 } else {
    let y = (x - 1.0) / (x + 1.0); let y2 = y * y
    let ln_x = 2.0 * y * (1.0 + y2 / 3.0 + y2 * y2 / 5.0 + y2 * y2 * y2 / 7.0)
    ln_x / 0.69314718056
  }
}
