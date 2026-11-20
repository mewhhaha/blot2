// Reconstruct the existing Gdev return shape, including its stable tie break.
/** @param {Float32Array | Uint32Array} rows */
export function selectFour(rows) {
  const actual = [];
  let winner = 0;
  for (let i = 0; i < 4; i++) {
    const here = i * 392 + 1, best = winner * 392 + 1;
    let better = rows[here] > rows[best];
    if (rows[here] === rows[best]) {
      better = rows[here + 2] < rows[best + 2];
      if (rows[here] === 0 && rows[here + 3] !== rows[best + 3]) {
        better = rows[here + 3] < rows[best + 3];
      }
    }
    if (better) winner = i;
    actual.push(...rows.subarray(here, here + rows[here - 1]));
  }
  return Float32Array.of(winner, ...actual);
}
