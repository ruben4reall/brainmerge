# Regenerates the How it works diagram and puts it back inside <div class="flow-stage"> of site/index.html.
# Usage, from anywhere: python3 scripts/site-flow/inject-flow.py
import os, subprocess
here = os.path.dirname(os.path.abspath(__file__))
page = os.path.join(here, '..', '..', 'site', 'index.html')
flow = subprocess.check_output(['node', os.path.join(here, 'gen-flow.cjs')]).decode().rstrip()
flow = '\n'.join('        ' + l if l.strip() else l for l in flow.split('\n'))
s = open(page, encoding='utf-8').read()
a = s.index('<div class="flow-stage">\n') + len('<div class="flow-stage">\n')
b = s.index('          </div>\n          <div class="flow-bar">')
s = s[:a] + flow + '\n' + s[b:]
open(page, 'w', encoding='utf-8').write(s)
print('injected', len(flow))
