// Hex Editor — Entropy Analysis
// Shannon entropy on 256-byte blocks with precomputed lookup table.
//
// Optimization: for full 256-byte blocks, entropy contribution for each
// byte count k is precomputed as table[k] = -(k/256)*log2(k/256).
// This eliminates all log2 calls for full blocks (vast majority).
// Partial blocks (last block < 256 bytes) use accurate log2 with
// range reduction + 6-term Taylor series.

///|
pub struct EntropyBlock {
  start : Int
  end : Int
  entropy : Double
} derive(Debug)

///|
/// Accurate log2 using range reduction + 6-term Taylor series.
fn log2_accurate(x : Double) -> Double {
  if x <= 0.0 { return 0.0 }
  // Range reduction: x = m * 2^e where 1 <= m < 2
  let mut m = x
  let mut e = 0
  while m >= 2.0 { m = m / 2.0; e = e + 1 }
  while m < 1.0 { m = m * 2.0; e = e - 1 }
  // ln(1+f) for f = m-1 in [0,1), Horner form, 6 terms
  let f = m - 1.0
  let ln_m = f * (1.0 + f * (-0.5 + f * (0.33333333333333 + f * (-0.25 + f * (0.2 + f * (-0.16666666666667))))))
  e.to_double() + ln_m / 0.6931471805599453
}

///|
/// Build entropy contribution lookup table for block_size=256.
/// table[k] = -(k/256)*log2(k/256) for k=0..256.
fn build_entropy_table() -> FixedArray[Double] {
  let table = FixedArray::make(257, 0.0)
  for k = 1; k <= 256; k = k + 1 {
    let p = k.to_double() / 256.0
    table[k] = -p * log2_accurate(p)
  }
  table
}

///|
/// Scan bytes in 256-byte blocks, compute Shannon entropy per block.
/// Full blocks use precomputed table (pure lookup, no log2 calls).
pub fn entropy_scan(bytes : Bytes) -> Array[EntropyBlock] {
  let len = bytes.length()
  let block_size = 256
  let table = build_entropy_table()
  let results : Array[EntropyBlock] = []
  let mut off = 0
  while off < len {
    let end = if off + block_size < len { off + block_size } else { len }
    let counts = FixedArray::make(256, 0)
    for j = off; j < end; j = j + 1 {
      let idx = bytes[j].to_int()
      counts[idx] = counts[idx] + 1
    }
    let mut h = 0.0
    let bsize = end - off
    if bsize == 256 {
      // Full block: pure table lookup, no log2 calls
      for k = 0; k < 256; k = k + 1 {
        if counts[k] > 0 { h = h + table[counts[k]] }
      }
    } else {
      // Partial block: compute with accurate log2
      let n = bsize.to_double()
      for k = 0; k < 256; k = k + 1 {
        if counts[k] > 0 {
          let p = counts[k].to_double() / n
          h = h - p * log2_accurate(p)
        }
      }
    }
    results.push({ start: off, end, entropy: h })
    off = end
  }
  results
}
