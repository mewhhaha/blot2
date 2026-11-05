// Zig 0.17 std.sort comparison order, retained for charged semantic work.
// Copyright (c) Zig contributors
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
namespace blot_check_source_sort;
enum Hint {increasing,decreasing,unknown}
struct Range {a:i64,b:i64,limit:i64,leftmost:bool,balanced:bool,partitioned:bool}
fn insertionContext(a:i64,b:i64,context) {assert(a<=b);var i=a+1;while i<b {var j=i;while j>a && context.lessThan(j,j-1) {context.swap(j,j-1);j-=1;}i+=1;}}
fn unguardedInsertionContext(a:i64,b:i64,context) {var i=a+1;while i<b {var j=i;while context.lessThan(j,j-1) {context.swap(j,j-1);j-=1;}i+=1;}}
fn siftDown(a:i64,target:i64,b:i64,context) {var current=target;while true {if current-a>0x3fffffffffffffff {break;}var child=(current-a)*2+a+1;if child>=b {break;}let next=child+1;if next<b && context.lessThan(child,next) {child=next;}if context.lessThan(child,current) {break;}context.swap(child,current);current=child;}}
fn heapContext(a:i64,b:i64,context) {assert(a<=b);var i=a+(b-a)/2;while i>a {i-=1;siftDown(a,i,b,context);}i=b;while i>a {i-=1;context.swap(a,i);siftDown(a,a,i,context);}}
fn pdqContext(a:i64,b:i64,context) {
    var limit:i64=0;var length=b-a;while length>1 {length>>=1;limit+=1;}var stack:Range[64];var range=Range{a,b,limit,true,true,true};var top:i64=0;
    while true {
        while true {let len=range.b-range.a;if len<=24 {if range.leftmost {insertionContext(range.a,range.b,context);}else {unguardedInsertionContext(range.a,range.b,context);}break;}if range.limit==0 {heapContext(range.a,range.b,context);break;}
            if !range.balanced {breakPatterns(range.a,range.b,context);range.limit-=1;}var pivot:i64=0;var hint=chosePivot(range.a,range.b,pivot,context);
            if hint==Hint.decreasing {reverseRange(range.a,range.b,context);pivot=(range.b-1)-(pivot-range.a);hint=Hint.increasing;}
            if range.balanced && range.partitioned && hint==Hint.increasing {if partialInsertionSort(range.a,range.b,context) {break;}}
            if range.a>a && !context.lessThan(range.a-1,pivot) {range.a=partitionEqual(range.a,range.b,pivot,context);continue;}
            var mid=pivot;let was_partitioned=partition(range.a,range.b,mid,context);let left_len=mid-range.a;let right_len=range.b-(mid+1);let threshold=len/8;let left_smaller=left_len<right_len;
            var smaller_len=right_len;var smaller_start=mid+1;var larger_start=range.a;var smaller_end=range.b;var larger_end=mid;var smaller_leftmost=false;var larger_leftmost=range.leftmost;
            if left_smaller {smaller_len=left_len;smaller_start=range.a;larger_start=mid+1;smaller_end=mid;larger_end=range.b;smaller_leftmost=range.leftmost;larger_leftmost=false;}
            let balanced=smaller_len>=threshold;stack[top]=Range{larger_start,larger_end,range.limit,larger_leftmost,balanced,was_partitioned};top+=1;range.a=smaller_start;range.b=smaller_end;range.leftmost=smaller_leftmost;range.balanced=true;range.partitioned=was_partitioned;
        }
        if top==0 {break;}top-=1;range=stack[top];
    }
}
fn partition(a:i64,b:i64,pivot:i64&,context)->bool {
    context.swap(a,pivot);var i=a+1;var j=b-1;while i<=j && context.lessThan(i,a) {i+=1;}while i<=j && !context.lessThan(j,a) {j-=1;}if i>j {context.swap(j,a);pivot=j;return true;}context.swap(i,j);i+=1;j-=1;
    var offsets_l:u8[64];var offsets_r:u8[64];var base_l=i;var base_r=j;var num_l:i64=0;var num_r:i64=0;var start_l:i64=0;var start_r:i64=0;
    while i<=j {let unknown=j+1-i;var left_split:i64=0;var right_split:i64=0;if num_l==0 {var available=unknown;if num_r==0 {available=unknown/2;}left_split=min(64,available);}if num_r==0 {right_split=min(64,unknown-left_split);}
        for k in 0..left_split {offsets_l[num_l]=k as u8;if !context.lessThan(i+k,a) {num_l+=1;}}i+=left_split;
        for k in 0..right_split {offsets_r[num_r]=k as u8;if context.lessThan(j-k,a) {num_r+=1;}}j-=right_split;
        let num=min(num_l,num_r);for m in 0..num {context.swap(base_l+offsets_l[start_l+m],base_r-offsets_r[start_r+m]);}num_l-=num;num_r-=num;start_l+=num;start_r+=num;
        if num_l==0 {start_l=0;base_l=i;}if num_r==0 {start_r=0;base_r=j;}
    }
    if num_l>0 {while num_l>0 {num_l-=1;context.swap(base_l+offsets_l[start_l+num_l],j);j-=1;}i=j+1;}
    if num_r>0 {while num_r>0 {num_r-=1;context.swap(base_r-offsets_r[start_r+num_r],i);i+=1;}j=i-1;}
    context.swap(j,a);pivot=j;return false;
}
fn partitionEqual(a:i64,b:i64,pivot:i64,context)->i64 {context.swap(a,pivot);var i=a+1;var j=b-1;while true {while i<=j && !context.lessThan(a,i) {i+=1;}while i<=j && context.lessThan(a,j) {j-=1;}if i>j {break;}context.swap(i,j);i+=1;j-=1;}return i;}
fn partialInsertionSort(a:i64,b:i64,context)->bool {var i=a+1;for ignored in 0..5 {while i<b && !context.lessThan(i,i-1) {i+=1;}if i==b {return true;}if b-a<50 {return false;}context.swap(i,i-1);if i-a>=2 {var j=i-1;while j>a {if !context.lessThan(j,j-1) {break;}context.swap(j,j-1);j-=1;}}if b-i>=2 {var j=i+1;while j<b {if !context.lessThan(j,j-1) {break;}context.swap(j,j-1);j+=1;}}}return false;}
fn breakPatterns(a:i64,b:i64,context) {let len=b-a;if len<8 {return;}var random=len as u64;var modulus:u64=1;while modulus<len as u64 {modulus<<=1;}var i=a+(len/4)*2-1;while i<=a+(len/4)*2+1 {random^=random<<13;random^=random>>7;random^=random<<17;var other=(random&(modulus-1)) as i64;if other>=len {other-=len;}context.swap(i,a+other);i+=1;}}
fn chosePivot(a:i64,b:i64,pivot:i64&,context)->Hint {let len=b-a;let i=a+len/4;let j=a+len/4*2;let k=a+len/4*3;var swaps:i64=0;if len>=8 {if len>=50 {sort3(i-1,i,i+1,swaps,context);sort3(j-1,j,j+1,swaps,context);sort3(k-1,k,k+1,swaps,context);}sort3(i,j,k,swaps,context);}pivot=j;if swaps==0 {return Hint.increasing;}if swaps==12 {return Hint.decreasing;}return Hint.unknown;}
fn sort3(a:i64,b:i64,c:i64,swaps:i64&,context) {if context.lessThan(b,a) {swaps+=1;context.swap(b,a);}if context.lessThan(c,b) {swaps+=1;context.swap(c,b);}if context.lessThan(b,a) {swaps+=1;context.swap(b,a);}}
fn reverseRange(a:i64,b:i64,context) {var i=a;var j=b-1;while i<j {context.swap(i,j);i+=1;j-=1;}}
