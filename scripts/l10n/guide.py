# SPDX-License-Identifier: GPL-3.0-or-later
"""產生 AO3 說明（AO3GuideView）的多語言版本：以英文版為來源機器翻譯，
簡體由繁體中文版以 OpenCC 轉換。術語一律附上英文原文。
用法：PYTHONPATH=<opencc> python3 guide.py ../../AO3Reader/Features/Browse/AO3GuideView.swift ../../AO3Reader/Resources/AO3Guide.json"""
import json, re, sys, time, urllib.parse, urllib.request

src = open(sys.argv[1]).read()

def parse(block_name):
    start = src.index(f'static let {block_name}: [Topic] = [')
    end = src.index('\n    ]\n', start)
    body = src[start:end]
    topics = []
    for m in re.finditer(r'Topic\(title: "((?:[^"\\]|\\.)*)", entries: \[(.*?)\n        \]\)', body, re.S):
        entries = [{'term': t, 'detail': d} for t, d in
                   re.findall(r'Entry\(term: "((?:[^"\\]|\\.)*)", detail: "((?:[^"\\]|\\.)*)"\)', m.group(2))]
        topics.append({'title': m.group(1), 'entries': entries})
    return topics

english = parse('english')
chinese = parse('chinese')

def gtx(text, tl):
    url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&dt=t&tl=' + tl
    data = urllib.parse.urlencode({'q': text}).encode()
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=30) as r:
                body = json.loads(r.read().decode())
            return ''.join(seg[0] for seg in body[0] if seg and seg[0])
        except Exception:
            time.sleep(2 ** attempt)
    raise RuntimeError('gtx failed')

def translate_lines(lines, tl):
    out = []
    for i in range(0, len(lines), 30):
        chunk = lines[i:i + 30]
        result = gtx('\n'.join(chunk), tl).split('\n')
        if len(result) != len(chunk):
            result = [gtx(line, tl) for line in chunk]
        out += [r.strip() for r in result]
        time.sleep(0.3)
    return out

def with_english(translated, original):
    return translated if translated.lower() == original.lower() or original in translated else f'{translated} ({original})'

langs = {'ja': 'ja', 'ko': 'ko', 'es': 'es', 'fr': 'fr', 'de': 'de', 'pt-BR': 'pt', 'it': 'it', 'ru': 'ru', 'uk': 'uk',
         'pl': 'pl', 'tr': 'tr', 'nl': 'nl', 'ar': 'ar', 'hi': 'hi', 'id': 'id', 'vi': 'vi', 'th': 'th'}
result = {}
flat = []
for topic in english:
    flat.append(topic['title'])
    for e in topic['entries']:
        flat += [e['term'], e['detail']]
for code, tl in langs.items():
    lines = translate_lines(flat, tl)
    it = iter(zip(flat, lines))
    topics = []
    for topic in english:
        en_title, title = next(it)
        entries = []
        for _ in topic['entries']:
            en_term, term = next(it)
            _, detail = next(it)
            entries.append({'term': with_english(term, en_term), 'detail': detail})
        topics.append({'title': with_english(title, en_title), 'entries': entries})
    result[code] = topics
    print(code, flush=True)

import opencc
t2s = opencc.OpenCC('tw2sp')
result['zh-Hans'] = [{'title': t2s.convert(t['title']),
                      'entries': [{'term': t2s.convert(e['term']), 'detail': t2s.convert(e['detail'])} for e in t['entries']]}
                     for t in chinese]
json.dump(result, open(sys.argv[2], 'w'), ensure_ascii=False, indent=1)
