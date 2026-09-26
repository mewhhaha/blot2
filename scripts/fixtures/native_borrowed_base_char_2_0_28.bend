type Char is Data:
  Chr{code: U32}

def Char.cmp(a: Char, b: Char) -> (Char & Char) & Cmp:
  match a b:
    case Chr{+x} Chr{+y}:
      ((Chr{x}, Chr{y}), U32.cmp(x, y))

def Char.to_u32(c: Char) -> U32:
  match c:
    case Chr{x}:
      x

def Char.from_u32(x: U32) -> Char:
  Chr{x}

def Char.is_eq(a: Char, b: Char) -> Bool:
  match a b:
    case Chr{x} Chr{y}:
      U32.is_eq(x, y)

def Char.is_digit(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57))

def Char.is_upper(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.and(U32.is_ge(x, 65), U32.is_le(x, 90))

def Char.is_lower(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.and(U32.is_ge(x, 97), U32.is_le(x, 122))

def Char.is_alpha(+c: Char) -> Bool:
  Bool.or(Char.is_upper(c), Char.is_lower(c))

def Char.is_space(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(U32.is_eq(x, 32), Bool.and(U32.is_ge(x, 9), U32.is_le(x, 13)))

def Char.to_upper(+c: Char) -> Char:
  Chr{U32.sub(Char.to_u32(c), U32.mul(Bool.to_u32(Char.is_lower(c)), 32))}

def Char.to_lower(+c: Char) -> Char:
  Chr{U32.add(Char.to_u32(c), U32.mul(Bool.to_u32(Char.is_upper(c)), 32))}

def Char.show(c: Char) -> String:
  SCon{c, SNil{}}
