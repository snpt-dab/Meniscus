# Rebuilds the shareable zip from the addon folder: python dist/build.py
# (run from the Meniscus folder). The version comes from Meniscus.toc.
import os, re, zipfile, glob, subprocess
# The version is 0.1.<n>, n = the number of the commit this build is for
# (commits so far + 1; run this before committing). The addon compares that
# last number between players to notice a newer version, and the updater
# compares the whole string.
n_commits = int(subprocess.check_output(['git', 'rev-list', '--count', 'HEAD']).decode().strip())
ver = '0.1.%d' % (n_commits + 1)
toc = open('Meniscus.toc', encoding='utf-8').read()
toc = re.sub(r'(## Version:\s*)\S+', lambda m: m.group(1) + ver, toc)
open('Meniscus.toc', 'w', encoding='utf-8', newline='\n').write(toc)
readme = open('README.txt', encoding='utf-8').read()
readme = re.sub(r'^Meniscus \S+ \(alpha\)', 'Meniscus %s (alpha)' % ver, readme)
open('README.txt', 'w', encoding='utf-8', newline='\n').write(readme)
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
