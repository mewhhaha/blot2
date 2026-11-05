"""Normalize port syntax without changing strings, comments or slice types."""
from pathlib import Path
import re
import argparse
ROOT=Path(__file__).resolve().parents[1]/'src'
LEX=re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|::|=>|\.\.|\s+|.',re.S)
def tokens(source):
    return [(m.group(),m.start(),m.end()) for m in LEX.finditer(source) if not m.group().isspace() and not m.group().startswith(('//','/*')) and m.group()]
def normalize(source,types):
    ts=tokens(source);edits={};typeslice={};stack=[]
    for i,(word,start,end) in enumerate(ts):
        if word=='[':stack.append(i)
        elif word==']' and stack:
            left=stack.pop();prefix=ts[left-1][0] if left else ''
            is_type=prefix in types or prefix=='>' or (prefix==']' and typeslice.get(left-1,False))
            typeslice[i]=is_type
            if i==left+2 and ts[left+1][0]==':' and not is_type:
                edits[ts[left+1][1]]=(ts[left+1][2],'..')
        if word=='self':edits[start]=(end,'receiver')
        if word=='block':
            previous=ts[i-1][0] if i else ''
            following=ts[i+1][0] if i+1<len(ts) else ''
            if following!='{' or previous=='.':edits[start]=(end,'block_')
        if word!='=>':continue
        left=i-1
        while left>=0 and ts[left][0] not in ('{','}',',',';','=>'):left-=1
        begin=left+1;j=begin
        while j<i:
            if not re.fullmatch(r'[A-Za-z_]\w*',ts[j][0]):j+=1;continue
            last=j
            while last+2<i and ts[last+1][0] in ('::','.') and re.fullmatch(r'[A-Za-z_]\w*',ts[last+2][0]):last+=2
            if last>j and any(ts[k][0]=='.' for k in range(j,last)):
                for k in range(j,last):edits[ts[k][1]]=(ts[k][2],'')
            j=last+1
    result=source
    for start,(end,text) in sorted(edits.items(),reverse=True):result=result[:start]+text+result[end:]
    result=re.sub(r'\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+(as!?\s+(?:u8|u16|u32|u64|i8|i16|i32|i64))\s+&',r'(\1 \2) &',result)
    return result
# Additional repairs used after the first actual parser run.
def finish_syntax(source):
    ts=tokens(source);edits={};pending_match=False;stack=[]
    def fix_pattern(first,last):
        j=first
        while j<last:
            if not re.fullmatch(r'[A-Za-z_]\w*',ts[j][0]):j+=1;continue
            end=j
            while end+2<last and ts[end+1][0] in ('::','.') and re.fullmatch(r'[A-Za-z_]\w*',ts[end+2][0]):end+=2
            if end>j and any(ts[k][0]=='.' for k in range(j,end)):
                for k in range(j,end):edits[ts[k][1]]=(ts[k][2],'')
            j=end+1
    for i,(word,start,end) in enumerate(ts):
        previous=ts[i-1][0] if i else '';following=ts[i+1][0] if i+1<len(ts) else ''
        if word=='match' and previous!='.' and following!=':' and previous not in ('fn','let','var'):pending_match=True
        if word=='{':stack.append({'match':pending_match,'pattern':True,'first':i+1});pending_match=False
        elif word=='}' and stack:stack.pop()
        elif stack and stack[-1]['match']:
            frame=stack[-1]
            if word=='=>' and frame['pattern']:fix_pattern(frame['first'],i);frame['pattern']=False
            elif word==',' and not frame['pattern']:frame['pattern']=True;frame['first']=i+1
        if word in ('guard','loop','simd','recursive','reusable'):
            keyword=False
            if word=='loop' and following=='{' and previous!='.':keyword=True
            if word in ('simd','recursive') and following in ('fn','extern','simd','recursive'):keyword=True
            if word=='reusable' and following in ('[','var','let'):keyword=True
            if not keyword:edits[start]=(end,word+'_')
        if word=='namespace' and i!=0:edits[start]=(end,'namespace_')
        if word=='varint' and (previous in ('.','fn') or following in ('(',':')):edits[start]=(end,'varint_')
        if word=='match' and (previous=='.' or following==':' or previous in ('let','var','fn')):edits[start]=(end,'match_')
        if word=='Error' and following=='.' and previous!='::':edits[start]=(end,'blot_error::Error')
    for start,(end,value) in sorted(edits.items(),reverse=True):source=source[:start]+value+source[end:]
    # Type defaults must not lex as assignment/comparison operators.
    def spaces(chunk):
        # A single annotation colon followed by a type. A namespace :: is
        # never an annotation, and a comparison is never a generic close.
        annotation=r'(?<!:):(?!:)[ \t]*(?:const[ \t]+)?(?:[A-Z]\w*|(?:[iu](?:8|16|32|64)|f32|f64|bool)|blot_\w+::\w+)'
        chunk=re.sub('('+annotation+r'[\w:<>,?\[\]. &]*)&=',r'\1& =',chunk)
        return re.sub('('+annotation+r'[^;={}\n]*<[^;={}\n]*)>=',r'\1> =',chunk)
    result=[];start=0
    for m in LEX.finditer(source):
        word=m.group()
        if word.startswith(('//','/*','"',"'")):
            result.append(spaces(source[start:m.start()]));result.append(word);start=m.end()
    result.append(spaces(source[start:]));return ''.join(result)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('paths',nargs='*',type=Path);args=parser.parse_args()
    paths=args.paths or sorted(ROOT.rglob('*.goose'))
    types={'bool','u8','u16','u32','u64','i8','i16','i32','i64','f32','f64'}
    for path in ROOT.rglob('*.goose'):
        types.update(re.findall(r'\b(?:struct|enum|type)\s+(\w+)',path.read_text()))
    count=0
    for path in paths:
        source=path.read_text();updated=finish_syntax(normalize(source,types))
        if updated!=source:path.write_text(updated);count+=1
    print(f'Normalized {count} source files')

