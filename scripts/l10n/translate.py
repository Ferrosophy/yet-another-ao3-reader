import json, re, sys, time, urllib.parse, urllib.request
sys.path.insert(0, '.')
from en import EN
PH = re.compile(r'%lld|%@')

def protect(s):
    i = 0
    def r(m):
        nonlocal i; tok = f'[{i}]'; i += 1; return tok
    return PH.sub(r, s), PH.findall(s)

def restore(s, phs):
    for i, p in enumerate(phs):
        s = re.sub(r'\[\s*%d\s*\]' % i, p.replace('%', '%%'), s, count=1)
    return s.replace('%%', '%')

def gtx(text, tl):
    url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&dt=t&tl=' + tl
    data = urllib.parse.urlencode({'q': text}).encode()
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=30) as r:
                body = json.loads(r.read().decode())
            return ''.join(seg[0] for seg in body[0] if seg and seg[0])
        except Exception as e:
            time.sleep(2 ** attempt)
    raise RuntimeError('gtx failed')

import os
CACHE = json.load(open('mt.json')) if os.path.exists('mt.json') else {}

def translate_all(tl, code):
    cached = CACHE.get(code, {})
    out = {k: v for k, v in cached.items() if k in EN}
    keys = [k for k in EN if k not in out]
    for start in range(0, len(keys), 40):
        chunk = keys[start:start+40]
        prot = [protect(EN[k]) for k in chunk]
        joined = '\n'.join(p[0].replace('\n', ' ') for p in prot)
        lines = gtx(joined, tl).split('\n')
        if len(lines) != len(chunk):
            lines = [gtx(p[0], tl) for p in prot]
        for k, (src, phs), line in zip(chunk, prot, lines):
            t = restore(line.strip(), phs)
            if sorted(PH.findall(t)) != sorted(phs):
                t = EN[k]  # 佔位符被破壞時退回英文
            out[k] = t
        time.sleep(0.3)
    return out

langs = {'ja':'ja','ko':'ko','es':'es','fr':'fr','de':'de','pt-BR':'pt','it':'it','ru':'ru','uk':'uk','pl':'pl','tr':'tr','nl':'nl','ar':'ar','hi':'hi','id':'id','vi':'vi','th':'th'}
result = {}
for code, tl in langs.items():
    result[code] = translate_all(tl, code)
    print(code, sum(1 for k in EN if result[code][k] == EN[k]), 'fallbacks/unchanged', flush=True)
json.dump(result, open('mt.json', 'w'), ensure_ascii=False, indent=1)
