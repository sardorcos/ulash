import json, sys, re
sys.path.insert(0, sys.argv[1])
from catalog import E
import catalog_app  # noqa: F401  (registers entries into E)
import catalog_ui  # noqa: F401
out = sys.argv[2]
keys = [k for k,*_ in E]
dups = {k for k in keys if keys.count(k) > 1}
assert not dups, dups
for idx, lang in enumerate(['ru','uz','en']):
    d = {'@@locale': lang}
    for key, ru, uz, en, ph in E:
        val = (ru, uz, en)[idx]
        # every placeholder used in template must appear in the message
        for name in ph:
            assert '{'+name in val, (key, lang, name)
        d[key] = val
        if lang == 'ru' and ph:
            d['@'+key] = {'placeholders': {n: {'type': t} for n, t in ph.items()}}
    with open(f'{out}/app_{lang}.arb', 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write('\n')
print(len(E), 'entries')
