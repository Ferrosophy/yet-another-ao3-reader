# SPDX-License-Identifier: GPL-3.0-or-later
"""AO3 固定標籤（分級、警告、分類）的內建翻譯，輸出 AO3Reader/Resources/FixedTags.json。
中文為人工翻譯，其他語言以 Google 翻譯產生。用法：python3 fixed_tags.py ../../AO3Reader/Resources/FixedTags.json"""
import json, sys, time, urllib.parse, urllib.request

ZH = {
    "General Audiences": "全年齡", "Teen And Up Audiences": "青少年及以上", "Mature": "成人", "Explicit": "限制級",
    "Not Rated": "未分級",
    "Creator Chose Not To Use Archive Warnings": "作者選擇不使用警告", "Choose Not To Use Archive Warnings": "作者選擇不使用警告",
    "No Archive Warnings Apply": "無適用警告", "Graphic Depictions Of Violence": "露骨暴力描寫",
    "Major Character Death": "主要角色死亡", "Rape/Non-Con": "強暴／非自願", "Underage Sex": "未成年性行為",
    "Underage": "未成年性行為",
    "F/F": "女/女", "F/M": "女/男", "M/M": "男/男", "Gen": "無 CP", "Multi": "多元", "Other": "其他",
}
ZH_HANS = {
    "General Audiences": "全年龄", "Teen And Up Audiences": "青少年及以上", "Mature": "成人", "Explicit": "限制级",
    "Not Rated": "未分级",
    "Creator Chose Not To Use Archive Warnings": "作者选择不使用警告", "Choose Not To Use Archive Warnings": "作者选择不使用警告",
    "No Archive Warnings Apply": "无适用警告", "Graphic Depictions Of Violence": "露骨暴力描写",
    "Major Character Death": "主要角色死亡", "Rape/Non-Con": "强奸／非自愿", "Underage Sex": "未成年性行为",
    "Underage": "未成年性行为",
    "F/F": "女/女", "F/M": "女/男", "M/M": "男/男", "Gen": "无 CP", "Multi": "多元", "Other": "其他",
}
# 分類標籤（F/F 等）在其他語言保留原文
KEEP = {"F/F", "F/M", "M/M", "Gen"}

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

tags = list(ZH)
result = {tag: {"zh-TW": ZH[tag], "zh-HK": ZH[tag], "zh-CN": ZH_HANS[tag]} for tag in tags}
langs = ['ja', 'ko', 'es', 'fr', 'de', 'pt', 'it', 'ru', 'uk', 'pl', 'tr', 'nl', 'ar', 'hi', 'id', 'vi', 'th']
source = [t for t in tags if t not in KEEP]
for lang in langs:
    lines = gtx('\n'.join(source), lang).split('\n')
    if len(lines) != len(source):
        lines = [gtx(t, lang) for t in source]
    for tag, line in zip(source, lines):
        result[tag][lang] = line.strip()
    print(lang, flush=True)
    time.sleep(0.3)
json.dump(result, open(sys.argv[1], 'w'), ensure_ascii=False, indent=1, sort_keys=True)
