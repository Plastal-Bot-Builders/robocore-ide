"""Turns `flutter test --machine` output into GitHub annotations."""
import json
import sys

names = {}
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    try:
        e = json.loads(line)
    except Exception:
        continue
    t = e.get('type')
    if t == 'testStart':
        names[e['test']['id']] = e['test']['name']
    elif t == 'error':
        msg = (e.get('error') or '').strip() + ' || ' + (e.get('stackTrace') or '').strip()[:900]
        msg = msg.replace('%', '%25').replace('\r', '').replace('\n', ' ¶ ')
        print(f"::error title={names.get(e.get('testID'), 'test')}::{msg[:2000]}")
    elif t == 'testDone' and e.get('result') != 'success' and not e.get('hidden'):
        print(f"::warning title=failed::{names.get(e.get('testID'), '?')} -> {e.get('result')}")
    elif t == 'print' and 'EXCEPTION' in (e.get('message') or ''):
        m = e['message'].replace('%', '%25').replace('\n', ' ¶ ')
        print(f"::error title=exception::{m[:2000]}")
