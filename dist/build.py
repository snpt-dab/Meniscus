# Rebuilds the shareable zip from the addon folder: python dist/build.py
# (run from the Meniscus folder). The version comes from Meniscus.toc.
import os, re, zipfile, glob
toc = open('Meniscus.toc', encoding='utf-8').read()
ver = re.search(r'## Version:\s*(\S+)', toc).group(1)
for old in glob.glob('dist/Meniscus-*.zip'): os.remove(old)
out = 'dist/Meniscus-%s-alpha.zip' % ver
n = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('dist', '.claude', '.git')]
        for f in files:
            if f == 'CLAUDE.md' or f.startswith('.') or '.bak' in f or f.endswith('.zip'): continue
            p = os.path.join(root, f)
            z.write(p, 'Meniscus/' + os.path.relpath(p, '.').replace(os.sep, '/')); n += 1
print(out, n, 'files', os.path.getsize(out), 'bytes')
