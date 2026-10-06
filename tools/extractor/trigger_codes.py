"""P1.13p: les codes de déclencheurs que la sim ne connaît pas (known_trigger), avec les sorts de classe qui les utilisent et leur description i18n.
Usage : PYTHONIOENCODING=utf-8 python tools/extractor/trigger_codes.py [N sorts par code]"""
import sys, json, collections
sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
from pathlib import Path
from spells import i18n_reader, known_trigger
t = i18n_reader(Path('game/content/Content/I18n/fr.bin'))
D = Path('game/content/Content/Data')
lv = json.load(open(D / 'spelllevelsdataroot.json', encoding='utf-8'))['objectsById']
sp = json.load(open(D / 'spellsdataroot.json', encoding='utf-8'))['objectsById']
d = json.load(open('game/data/spells.json', encoding='utf-8'))
cls = {g for v in d['grades'].values() for g in v}
by = collections.defaultdict(set)
for g in cls:
    row = lv.get(str(g - 1000000))
    if not row: continue
    for e in row['effects'] + row.get('criticalEffect', []):
        for c in str(e.get('triggers', '')).split('|'):
            if c and c != 'I' and not known_trigger(c): by[(c, e['effectId'])].add(row['spellId'])
print(len(by), 'couples (code, effet) inconnus')
for (c, eid), ids in sorted(by.items(), key=lambda kv: -len(kv[1]))[:int(sys.argv[1]) if len(sys.argv)>1 else 14]:
    print('\n==', c, 'effet', eid, '|', len(ids), 'sorts')
    for i in sorted(ids)[:2]:
        s = sp[str(i)]
        print('  ', t(s['nameId']), '|', t(s['descriptionId'])[:900].replace('\n', ' '))
