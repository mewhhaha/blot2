import Base

# Bend's JS reader rounds through binary64, while its native reader uses
# strtof. Their candidates differ by at most one F32 ULP. Exact decimal
# midpoint comparisons remove that double-rounding difference, including
# subnormals, ties-to-even, and the finite/infinity boundary.
type Decimal is Data:
  DecimalZero{}
  Decimal{digits: String, positive: Nat, negative: Nat}

type Exponent is Data:
  Exponent{positive: Nat, negative: Nat}

def leading_zeroes(digits: String) -> String:
  match digits:
    case SCon{Chr{48}, tail}:
      leading_zeroes(tail)
    case other:
      other

def decimal(digits: String, fractional: Nat, exponent: Exponent) -> Decimal:
  match digits exponent:
    case SNil{} _:
      DecimalZero{}
    case +digits Exponent{positive, negative}:
      Decimal{digits, Nat.add(Nat.sub(String.length(digits), 1n), positive), Nat.add(fractional, negative)}

def exponent_digits(chars: String, value: Nat, +limit: Nat) -> Maybe<&2, Nat>:
  match chars:
    case SNil{}:
      Some{value}
    case SCon{Chr{+code}, tail}:
      do Maybe<&2, Nat>:
        valid : Unit <- Bool.pick(Maybe<&2, Unit>, Bool.and(U32.is_ge(code, 48), U32.is_le(code, 57)), Some{Unit{}}, None{})
        exponent_digits(tail, Nat.min(limit, Nat.add(Nat.mul(value, 10n), U32.to_nat(U32.sub(code, 48)))), limit)

def exponent(chars: String, limit: Nat) -> Maybe<&2, Exponent>:
  match chars:
    case SNil{}:
      None{}
    case SCon{Chr{45}, tail}:
      do Maybe<&2, Exponent>:
        value : Nat <- exponent_digits(tail, 0n, limit)
        return Exponent{0n, value}
    case SCon{Chr{43}, tail}:
      do Maybe<&2, Exponent>:
        value : Nat <- exponent_digits(tail, 0n, limit)
        return Exponent{value, 0n}
    case chars:
      do Maybe<&2, Exponent>:
        value : Nat <- exponent_digits(chars, 0n, limit)
        return Exponent{value, 0n}

def significand(chars: String, reversed: String, fractional: Nat, +point: Bool, +limit: Nat) -> Maybe<&2, Decimal>:
  match chars:
    case SNil{}:
      Some{decimal(leading_zeroes(String.reverse(reversed)), fractional, Exponent{0n, 0n})}
    case SCon{Chr{46}, tail}:
      significand(tail, reversed, fractional, True{}, limit)
    case SCon{Chr{101}, tail}:
      do Maybe<&2, Decimal>:
        scale : Exponent <- exponent(tail, limit)
        return decimal(leading_zeroes(String.reverse(reversed)), fractional, scale)
    case SCon{Chr{69}, tail}:
      do Maybe<&2, Decimal>:
        scale : Exponent <- exponent(tail, limit)
        return decimal(leading_zeroes(String.reverse(reversed)), fractional, scale)
    case SCon{Chr{code}, tail}:
      +number = {code : U32}
      do Maybe<&2, Decimal>:
        valid : Unit <- Bool.pick(Maybe<&2, Unit>, Bool.and(U32.is_ge(number, 48), U32.is_le(number, 57)), Some{Unit{}}, None{})
        significand(tail, SCon{Chr{number}, reversed}, Nat.add(fractional, Bool.pick(Nat, point, 1n, 0n)), point, limit)

def multiply_digits(reversed: String, +factor: U32, carry: U32, result: String) -> String:
  match reversed carry:
    case SNil{} 0:
      result
    case SNil{} other:
      U32.show(other) ++ result
    case SCon{Chr{code}, tail} carry:
      +value = U32.add(U32.mul(U32.sub(code, 48), factor), carry)
      multiply_digits(tail, factor, U32.div(value, 10), SCon{Chr{U32.add(48, U32.mod(value, 10))}, result})

def multiply_power(power: Nat, +factor: U32, digits: String) -> String:
  match power:
    case 0n:
      digits
    case 1n+rest:
      multiply_power(rest, factor, multiply_digits(String.reverse(digits), factor, 0, SNil{}))

def midpoint(+lower: U32) -> Decimal:
  +biased = U32.shrn(lower, 23n)
  +mantissa = U32.and(lower, 8388607)
  coefficient = U32.add(U32.mul(Bool.pick(U32, U32.is_eq(biased, 0), mantissa, U32.add(mantissa, 8388608)), 2), 1)
  +power = U32.to_nat(Bool.pick(U32, U32.is_eq(biased, 0), 1, biased))
  +negative = Nat.sub(151n, power)
  +digits = multiply_power(negative, 5, multiply_power(Nat.sub(power, 151n), 2, U32.show(coefficient)))
  Decimal{digits, Nat.sub(String.length(digits), 1n), negative}

def compare_digits(left: String, right: String, order: Cmp) -> Cmp:
  match left right order:
    case _ _ LT{}:
      LT{}
    case _ _ GT{}:
      GT{}
    case SNil{} SNil{} EQ{}:
      EQ{}
    case SNil{} SCon{Chr{head}, tail} EQ{}:
      compare_digits(SNil{}, tail, U32.cmp(48, head))
    case SCon{Chr{head}, tail} SNil{} EQ{}:
      compare_digits(tail, SNil{}, U32.cmp(head, 48))
    case SCon{Chr{a}, at} SCon{Chr{b}, bt} EQ{}:
      compare_digits(at, bt, U32.cmp(a, b))

def compare(left: Decimal, right: Decimal) -> Cmp:
  match left right:
    case DecimalZero{} DecimalZero{}:
      EQ{}
    case DecimalZero{} _:
      LT{}
    case _ DecimalZero{}:
      GT{}
    case Decimal{a, ap, an} Decimal{b, bp, bn}:
      compare_digits(a, b, Nat.cmp(Nat.add(ap, bn), Nat.add(bp, an)))

def upper_choice(order: Cmp, +bits: U32) -> U32:
  match order:
    case LT{}:
      bits
    case EQ{}:
      Bool.pick(U32, U32.is_eq(U32.and(bits, 1), 0), bits, U32.add(bits, 1))
    case GT{}:
      U32.add(bits, 1)

def upper(+bits: U32, exact: Decimal) -> U32:
  match bits:
    case 2139095040:
      2139095040
    case bits:
      upper_choice(compare(exact, midpoint(bits)), bits)

def lower_choice(order: Cmp, +bits: U32, exact: Decimal) -> U32:
  match order:
    case LT{}:
      U32.sub(bits, 1)
    case EQ{}:
      Bool.pick(U32, U32.is_eq(U32.and(bits, 1), 0), bits, U32.sub(bits, 1))
    case GT{}:
      upper(bits, exact)

def rounded(+bits: U32, +exact: Decimal) -> U32:
  match bits exact:
    case _ DecimalZero{}:
      0
    case 0 exact:
      upper(0, exact)
    case bits exact:
      lower_choice(compare(exact, midpoint(U32.sub(bits, 1))), bits, exact)

def from_bits(value: U32) -> F32:
  U32{bits} = value
  F32{bits}

def candidate(parsed: Maybe<&2, F32>, +text: String) -> Maybe<&2, F32>:
  match parsed:
    case None{}:
      None{}
    case Some{value}:
      +bits = F32.bits(value)
      do Maybe<&2, F32>:
        valid : Unit <- Bool.pick(Maybe<&2, Unit>, U32.is_le(bits, 2139095040), Some{Unit{}}, None{})
        exact : Decimal <- significand(text, SNil{}, 0n, False{}, Nat.add(String.length(text), 400n))
        return from_bits(rounded(bits, exact))

def read(+text: String) -> Maybe<&2, F32>:
  candidate(F32.read(text), text)
