import { compileAndRun, equal } from "./compile_helpers.ts";

const declarations =
  `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return @u32.add owner value }
impl Flag : Source Bool = { type Item = F32, const get = func value => return if value then 7.5 else 9.5, const show = func owner => return func value => return @u32.add (@f32.to_u32 value) (if owner then 0 else 2) }
type Item = exists [a] where { Source a } => (a, Source.Item a)
const make: Bool -> Item = func flag => return if flag then pack [U32] (20,22) as Item else pack [Bool] (true,7.5) as Item
const reseal = func (item: Item) => return unpack item as [a] value in pack [a] value as Item
const read = func (item: Item) => return unpack item as [a] value in Source.show (@product.get value 0) (@product.get value 1)
const both = func (left: Item) => return func (right: Item) => return @u32.add (read left) (read right)
`;

Deno.test("associated package payloads retain heterogeneous representations across resealing", async () => {
  for (const asynchronous of [false, true]) {
    await compileAndRun(
      declarations +
        `entry const answer = func (flag: Bool) => return read (reseal (make flag))
entry const collection = func (flag: Bool) => return do:
  let items = #[reseal (make flag), make false]
  break both (@array.get items 0) (@array.get items 1)
`,
      async (guest) => {
        const call = async (name: string, flag: boolean) => {
          if (asynchronous) return await guest.callAsync(name, flag);
          return guest.call(name, flag);
        };
        for (let index = 0; index < 96; index++) {
          const flag = index % 2 === 0;
          let expected = 7;
          if (flag) expected = 42;
          equal(await call("answer", flag), expected);
          equal(await call("collection", flag), expected + 7);
        }
        const warmed = guest.memoryBytes();
        for (let index = 0; index < 96; index++) {
          equal(await call("collection", false), 14);
        }
        equal(guest.memoryBytes(), warmed);
      },
      { prelude: "none", asynchronous },
    );
  }
});
