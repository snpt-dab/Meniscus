# Rebuilds the shareable zip from the addon folder: python dist/build.py
# (run from the MinimalUI folder). The version comes from MinimalUI.toc.
import os, re, zipfile, glob
toc = open('MinimalUI.toc', encoding='utf-8').read()
ver = re.search(r'## Version:\s*(\S+)', toc).group(1)
for old in glob.glob('dist/MinimalUI-*.zip'): os.remove(old)
out = 'dist/MinimalUI-%s-alpha.zip' % ver
n = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('dist', '.claude', '.git')]
        for f in files:
            if f == 'CLAUDE.md' or '.bak' in f or f.endswith('.zip'): continue
            p = os.path.join(root, f)
            z.write(p, 'MinimalUI/' + os.path.relpath(p, '.').replace(os.sep, '/')); n += 1
print(out, n, 'files', os.path.getsize(out), 'bytes')
