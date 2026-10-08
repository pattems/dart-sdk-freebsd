#!/usr/bin/env python3
"""Compare two source tarballs entry by entry: name, type, mode, link target
and SHA-256 of the contents. Timestamps and archive order are ignored.

usage: tarcmp.py A.tar.xz B.tar.xz
"""
import hashlib
import sys
import tarfile


def index(path):
    out = {}
    with tarfile.open(path, 'r:*') as t:
        for m in t:
            name = m.name.rstrip('/')
            if m.isfile():
                h = hashlib.sha256()
                f = t.extractfile(m)
                for chunk in iter(lambda: f.read(1 << 20), b''):
                    h.update(chunk)
                val = ('file', oct(m.mode & 0o7777), h.hexdigest())
            elif m.isdir():
                val = ('dir', oct(m.mode & 0o7777), '')
            elif m.issym():
                val = ('symlink', '', m.linkname)
            elif m.islnk():
                val = ('hardlink', '', m.linkname)
            else:
                val = ('other', oct(m.mode & 0o7777), '')
            out[name] = val
    return out


a, b = index(sys.argv[1]), index(sys.argv[2])
only_a = sorted(set(a) - set(b))
only_b = sorted(set(b) - set(a))
differ = sorted(n for n in set(a) & set(b) if a[n] != b[n])
print(f'entries: {len(a)} vs {len(b)}')
print(f'only in first: {len(only_a)}, only in second: {len(only_b)}, '
      f'different: {len(differ)}')
for label, names in (('only in first', only_a), ('only in second', only_b)):
    for n in names[:25]:
        print(f'  {label}: {n} {a.get(n) or b.get(n)}')
for n in differ[:25]:
    print(f'  differs: {n}\n    first:  {a[n]}\n    second: {b[n]}')
sys.exit(0 if not (only_a or only_b or differ) else 1)
