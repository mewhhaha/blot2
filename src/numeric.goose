// Exact decimal → IEEE binary32 rounding without an intermediate binary64.
// Every binary32 midpoint has a finite decimal expansion with fewer than 200
// significant digits. Retaining 200 plus a sticky bit therefore decides ties.
import std;
struct DecimalBig { words: u32[40], used: u32 }
fn decimal_small(n: u32) -> DecimalBig {
    var b = DecimalBig { .. }; b.words[0] = n; b.used = 1; return b;
}
fn decimal_mul(b: DecimalBig&, n: u32) -> bool {
    var carry:u64 = 0;
    for i in b.used {
        let product = b.words[i] as u64 * n + carry;
        b.words[i] = product as! u32; carry = product >> 32;
    }
    if carry != 0 {
        if b.used == 40 { return false; }
        b.words[b.used] = carry as u32; b.used++;
    }
    return true;
}
fn decimal_add(b: DecimalBig&, n: u32) -> bool {
    var carry:u64 = n;
    for i in b.used {
        let sum = b.words[i] as u64 + carry;
        b.words[i] = sum as! u32; carry = sum >> 32;
    }
    if carry != 0 {
        if b.used == 40 { return false; }
        b.words[b.used] = carry as u32; b.used++;
    }
    return true;
}
fn decimal_compare(a: DecimalBig, b: DecimalBig) -> i32 {
    var i:i64 = 40;
    while i > 0 { i--; if a.words[i] < b.words[i] { return -1; } if a.words[i] > b.words[i] { return 1; } }
    return 0;
}
fn parse_decimal_f32(text: const u8[:]) -> u32, bool {
    if text.len == 0 || text.len > 16777216 { return 0, false; }
    var digits = decimal_small(0);
    var kept:i64 = 0; var significant:i64 = 0; var fractional:i64 = 0;
    var decimal_point = false; var any_digit = false; var nonzero = false; var sticky = false;
    var at:i64 = 0;
    while at < text.len && text[at] != 'e' && text[at] != 'E' {
        let ch = text[at]; at++;
        if ch == '.' {
            if decimal_point { return 0, false; } decimal_point = true; continue;
        }
        if ch < '0' || ch > '9' { return 0, false; }
        any_digit = true; if decimal_point { fractional++; }
        let digit = ch - '0';
        if digit != 0 { nonzero = true; }
        if nonzero {
            significant++;
            if kept < 200 {
                if !decimal_mul(digits, 10) || !decimal_add(digits, digit) { return 0, false; }
                kept++;
            } else if digit != 0 { sticky = true; }
        }
    }
    if !any_digit { return 0, false; }
    var exponent:i64 = 0; var negative = false;
    if at < text.len {
        at++;
        if at < text.len && (text[at] == '+' || text[at] == '-') { negative = text[at] == '-'; at++; }
        let start = at;
        while at < text.len {
            let ch = text[at]; at++;
            if ch < '0' || ch > '9' { return 0, false; }
            // Saturation dominates the largest admitted source literal length.
            if exponent < 100000000 { exponent = min(100000000, exponent * 10 + ch - '0'); }
        }
        if at == start { return 0, false; }
    }
    if negative { exponent = -exponent; }
    if !nonzero { return 0, true; }
    exponent = exponent - fractional + significant - kept;
    let order = kept + exponent;
    if order > 40 { return 0x7f800000, true; }
    if order < -46 { return 0, true; }
    var numerator = digits; var denominator = decimal_small(1);
    if exponent >= 0 { for i in exponent { if !decimal_mul(numerator, 10) { return 0, false; } } }
    else { for i in -exponent { if !decimal_mul(denominator, 10) { return 0, false; } } }
    var low:u32 = 0; var high:u32 = 0x7f800000;
    while low < high {
        let mid = low + (high - low) / 2;
        let encoded_exp = (mid >> 23) & 255;
        let mantissa = if encoded_exp == 0 { mid & 0x7fffff } else { (mid & 0x7fffff) | 0x800000 };
        let binary_exp:i64 = if encoded_exp == 0 { -150 } else { encoded_exp as i64 - 151 };
        var left = numerator; var right = denominator;
        if !decimal_mul(right, 2 * mantissa + 1) { return 0, false; }
        if binary_exp >= 0 { for i in binary_exp { if !decimal_mul(right, 2) { return 0, false; } } }
        else { for i in -binary_exp { if !decimal_mul(left, 2) { return 0, false; } } }
        var comparison = decimal_compare(left, right);
        if comparison == 0 && sticky { comparison = 1; }
        if comparison < 0 || (comparison == 0 && (mid & 1) == 0) { high = mid; }
        else { low = mid + 1; }
    }
    return low, true;
}
