# 介面多語系

`AO3Reader/Resources/Localizable.xcstrings` 由以下流程產生（鍵為原始碼中的繁體中文字面量）：

1. `python3 extract.py ../../AO3Reader keys.json` — 擷取所有含中文的字串字面量
2. `en.py` — 人工撰寫的英文（作為機器翻譯的樞紐語言）
3. `python3 translate.py` — 英文 → 17 種語言（Google 翻譯，結果快取於 `mt.json`）
4. `overrides.py` — 人工修正易被誤譯的短詞（字重、點擊、訂閱等）
5. `python3 build.py ../../AO3Reader/Resources/Localizable.xcstrings` — 以 OpenCC 產生簡體與台灣 / 香港 / 澳門繁體，合併輸出

需要 `pip install opencc-python-reimplemented`。新增介面文字後重跑 1 → 5，並在 `en.py` 補上英文。
