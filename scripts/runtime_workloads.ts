/** Independent integer/F32 reference models for the measured loop kernels. */
const bits = new DataView(new ArrayBuffer(4));
function f32bits(value: number) {
  bits.setFloat32(0, value, true);
  return bits.getUint32(0, true);
}
export const seeds = [0, 1, 7, 40, 255, 65535, 0xffffffff];
const recurrence = {
  iterations: 1024,
  encode: (value: number) => value >>> 0,
  reference(seed: number) {
    let state = seed >>> 0, total = 0;
    for (let i = 0; i < 1024; i++) {
      state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
      total = (total + state) >>> 0;
    }
    return total;
  },
};
const affine = {
  iterations: 128,
  encode: f32bits,
  reference(seed: number) {
    let state = Math.fround(seed);
    for (let i = 0; i < 128; i++) {
      state = Math.fround(Math.fround(state * Math.fround(1.0001)) + 0.5);
    }
    return state;
  },
};
export const workloads = [
  { name: "recurrence", ...recurrence },
  { name: "affine_loop", ...affine },
  { name: "generic_recurrence", ...recurrence },
  { name: "generic_affine", ...affine },
  { name: "generic_pair", ...recurrence },
];
