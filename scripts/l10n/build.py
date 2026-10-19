import json, sys
sys.path.insert(0, '.')
from opencc import OpenCC
from en import EN, SKIP
from overrides import OVERRIDES
mt = json.load(open('mt.json'))
keys = [k for k in json.load(open('keys.json')) if k not in SKIP]

to_hans = OpenCC('tw2sp')   # 台灣正體 → 大陸簡體（含用語）
to_tw = OpenCC('t2tw')      # 只統一台灣字形，不改詞彙

# 用語修正（字形轉換不處理的詞彙差異）
HANS_FIX = {'接口': '界面', '缺省': '默认', '帐号': '账号', '帐户': '账户', '字体档': '字体文件', '档案': '文件', '纪录': '记录'}
# 順序重要：較長的詞先替換
TW_FIX = {'用戶名稱': '使用者名稱', '用戶名': '使用者名稱', '用戶': '使用者', '字體': '字型', '網絡': '網路', '軟件': '軟體', '導入': '匯入', '默認': '預設', '信息': '資訊', '視頻': '影片'}
HK_FIX = {'使用者名稱': '用戶名稱', '使用者': '用戶', '帳號': '帳戶', '字型': '字體', '網路': '網絡', '軟體': '軟件', '資料夾': '文件夾'}

def apply(text, table):
    for a, b in table.items():
        text = text.replace(a, b)
    return text

zh_hans, zh_tw, zh_hk = {}, {}, {}
for k in keys:
    zh_hans[k] = apply(to_hans.convert(k), HANS_FIX)
    tw = apply(to_tw.convert(k), TW_FIX)
    zh_tw[k] = tw
    zh_hk[k] = apply(tw, HK_FIX)

locales = {'en': EN, 'zh-Hans': zh_hans, 'zh-Hant': zh_tw, 'zh-Hant-TW': zh_tw, 'zh-Hant-HK': zh_hk, 'zh-Hant-MO': zh_hk}
for lang, table in mt.items():
    merged = dict(table); merged.update(OVERRIDES.get(lang, {}))
    locales[lang] = merged

catalog = {'sourceLanguage': 'zh-Hant', 'version': '1.0', 'strings': {}}
for k in keys:
    locs = {}
    for lang, table in locales.items():
        value = table.get(k)
        if value is None: continue
        locs[lang] = {'stringUnit': {'state': 'translated', 'value': value}}
    catalog['strings'][k] = {'extractionState': 'manual', 'localizations': locs}
json.dump(catalog, open(sys.argv[1], 'w'), ensure_ascii=False, indent=2, sort_keys=True)
for k in ['帳號', '用戶', '字體', '介面字體', '搜尋', '預設', '用戶名或電子郵件', '登入狀態以 AO3 的 Cookie 保存在本機，依來源網域分開。本應用沒有自己的帳號系統，也不保存你的密碼。']:
    print(k, '|', zh_hans[k], '|', zh_tw[k], '|', zh_hk[k])
print(len(keys), 'keys,', len(locales), 'locales')
