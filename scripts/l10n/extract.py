import re, sys, json, pathlib
han = re.compile(r'[一-鿿]')
INT_HINTS = re.compile(r'^(code|expected|got|result|count|index|Int\(.*\)|.*\.count|status)$')

def parse_interp(src, i):
    # src[i] is just after '\(' ; return (expr, new_index after ')')
    depth = 1; j = i
    while j < len(src):
        c = src[j]
        if c == '"':
            j = skip_string(src, j)[1]; continue
        if c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: return src[i:j], j + 1
        j += 1
    return src[i:], len(src)

def skip_string(src, i):
    # returns (pieces, end_index); pieces = list of ('t', text) / ('x', expr)
    pieces = []
    if src.startswith('"""', i):
        j = i + 3
        buf = ''
        while j < len(src):
            if src.startswith('"""', j): 
                pieces.append(('t', buf)); return pieces, j + 3
            c = src[j]
            if c == '\\':
                n = src[j+1]
                if n == '(':
                    pieces.append(('t', buf)); buf = ''
                    expr, j = parse_interp(src, j + 2); pieces.append(('x', expr)); continue
                if n == '\n': j += 2; buf += '\x00JOIN\n'; continue
                buf += {'n': '\n', 't': '\t', '"': '"', '\\': '\\'}.get(n, n); j += 2; continue
            buf += c; j += 1
        return pieces, j
    j = i + 1; buf = ''
    while j < len(src):
        c = src[j]
        if c == '"': pieces.append(('t', buf)); return pieces, j + 1
        if c == '\\':
            n = src[j+1]
            if n == '(':
                pieces.append(('t', buf)); buf = ''
                expr, j = parse_interp(src, j + 2); pieces.append(('x', expr)); continue
            buf += {'n': '\n', 't': '\t', '"': '"', '\\': '\\'}.get(n, n); j += 2; continue
        if c == '\n': break
        buf += c; j += 1
    return pieces, j

def normalize_multiline(text):
    # 依 Swift 規則：去掉第一個換行、依結尾縮排去除前綴，處理行尾反斜線
    lines = text.split('\n')
    if lines and lines[0].strip() == '': lines = lines[1:]
    indent = len(lines[-1]) if lines and lines[-1].strip() == '' else 0
    if lines and lines[-1].strip() == '': lines = lines[:-1]
    out = '\n'.join(l[indent:] for l in lines)
    return out.replace('\x00JOIN\n', '')

# 內容本身已分語言撰寫、以 verbatim 顯示的檔案不進字串目錄
SKIP_FILES = {'AO3GuideView.swift'}

keys = {}
for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.swift')):
    if f.name in SKIP_FILES: continue
    src = f.read_text(); i = 0
    while i < len(src):
        if src.startswith('//', i):
            i = src.find('\n', i); i = len(src) if i < 0 else i; continue
        if src.startswith('/*', i):
            i = src.find('*/', i) + 2; continue
        if src[i] == '"':
            multi = src.startswith('"""', i)
            pieces, end = skip_string(src, i)
            key = ''
            for kind, val in pieces:
                if kind == 't': key += val.replace('%', '%%')
                else: key += '%lld' if INT_HINTS.match(val.strip()) else '%@'
            if multi: key = normalize_multiline(key)
            if han.search(key):
                keys.setdefault(key, f'{f.name}')
            i = end; continue
        i += 1
json.dump(keys, open(sys.argv[2], 'w'), ensure_ascii=False, indent=1)
print(len(keys))
