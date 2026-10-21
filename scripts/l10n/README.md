# 界面多语言

`AO3Reader/Resources/Localizable.xcstrings` 由以下流程产生（键为原代码中的繁体中文本面量）：

1. `python3 extract.py ../../AO3Reader keys.json` — 截取所有含中文的字符串字面量
2. `en.py` — 人工撰写的英文（作为机器翻译的枢纽语言）
3. `python3 translate.py` — 英文 → 17 种语言（Google 翻译，结果缓存于 `mt.json`）
4. `overrides.py` — 人工修正易被误译的短词（字重、点击、订阅等）
5. `python3 build.py ../../AO3Reader/Resources/Localizable.xcstrings` — 以 OpenCC 产生简体与台湾 / 香港 / 澳门繁体，合并输出

需要 `pip install opencc-python-reimplemented`。添加界面文本后重跑 1 → 5，并在 `en.py` 补上英文。
