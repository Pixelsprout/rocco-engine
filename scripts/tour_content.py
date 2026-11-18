"""Checks the Tour content: the Tutorial pages and the Tour step sources.

    python3 scripts/tour_content.py check
        fails if a Tutorial page has a bad tour marker or a desktop-only part
        outside a tour:skip block, if a Tour step source is missing or has a
        header that the site cannot point at the release URLs, or if a Tour
        step has a shaders.json.

The marker rules match the site's Tour step builder, so a page that passes
here also builds there.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_OPEN = '<!-- tour:skip -->'
SKIP_CLOSE = '<!-- /tour:skip -->'
# The tour-only text sits inside the comment, so GitHub and the desktop Guide do not show it.
ONLY_OPEN = '<!-- tour-only'
ONLY_CLOSE = '-->'
ANY_MARKER = re.compile(r'<!--\s*/?tour\b')
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
DESKTOP_FENCES = {'sh', 'diff'}
DESKTOP_SECTIONS = ('Before you start', 'Run the game', 'Play the game', 'Test ', 'Get the ')
STUB = '00-start'


def walk(text):
    """Yields (line number, line, kind) where kind is 'fence-open', 'fence',
    'marker' or 'text', and the open tour block as (kind, line) or None."""
    fence = None
    block = None
    for number, line in enumerate(text.split('\n'), 1):
        match = FENCE.match(line)
        opener = match.group(1) if match else None
        if fence:
            if opener and opener[0] == fence[0] and len(opener) >= len(fence) and line.strip() == opener:
                fence = None
            yield number, line, 'fence', block
            continue
        if opener:
            fence = opener
            yield number, line, 'fence-open', block
            continue
        marker = line.strip()
        if marker == SKIP_OPEN or marker == ONLY_OPEN:
            yield number, line, 'marker', block
            block = block or ('tour:skip' if marker == SKIP_OPEN else 'tour-only', number)
            continue
        if marker == SKIP_CLOSE or (marker == ONLY_CLOSE and block and block[0] == 'tour-only'):
            yield number, line, 'marker', block
            block = None
            continue
        yield number, line, 'text', block
    yield None, None, 'end', block


def marker_problems(text, page):
    problems = []
    for number, line, kind, block in walk(text):
        marker = line.strip() if line is not None else None
        if kind == 'end':
            if block:
                problems.append(f'{page}:{block[1]} opens a {block[0]} block that never closes')
        elif kind == 'marker' and marker in (SKIP_OPEN, ONLY_OPEN):
            opens = 'tour:skip' if marker == SKIP_OPEN else 'tour-only'
            if block:
                problems.append(f'{page}:{number} opens a {opens} block inside the {block[0]} block from line {block[1]}')
        elif kind == 'marker' and marker == SKIP_CLOSE:
            if not block or block[0] != 'tour:skip':
                problems.append(f'{page}:{number} closes a tour:skip block that is not open')
        elif kind == 'text' and ANY_MARKER.search(line):
            problems.append(f'{page}:{number} has the unknown tour marker {marker}')
    return problems


def desktop_problems(text, page):
    problems = []
    for number, line, kind, block in walk(text):
        if block and block[0] == 'tour:skip':
            continue
        if kind == 'fence-open':
            info = line.strip().lstrip('`~').strip()
            if info in DESKTOP_FENCES:
                problems.append(f'{page}:{number} has a {info} block outside a tour:skip block')
        elif kind == 'text' and line.startswith('## ') and line[3:].startswith(DESKTOP_SECTIONS):
            problems.append(f'{page}:{number} has the desktop-only section "{line[3:]}" outside a tour:skip block')
    return problems


def header_problems(source, rel):
    header = next((line for line in source.split('\n') if line.startswith('app ')), '')
    problems = []
    for path in re.findall(r'"(\.\.?/[^"]*)"', header):
        match = release.LOCAL_PATH.fullmatch(f'"{path}"')
        name = match and (match.group(2) or 'platform')
        if name not in release.DOCS_BUNDLES:
            problems.append(f'{rel}: the header names "{path}", which has no release URL marker')
    return problems


def step_problems(root):
    def rel(*parts):
        return '/'.join(parts)

    pages = sorted(name[:-3] for name in os.listdir(os.path.join(root, 'guide', 'tutorial')) if name.endswith('.md'))
    problems = []
    for page in pages:
        path = rel('guide', 'tutorial', page + '.md')
        with open(os.path.join(root, path), encoding='utf-8') as f:
            text = f.read()
        problems += marker_problems(text, path) + desktop_problems(text, path)
    for step in [STUB] + pages:
        source = rel('examples', 'tutorial', step, 'main.roc')
        if not os.path.isfile(os.path.join(root, source)):
            role = 'the starting source of step 1' if step == STUB else f'the answer of guide/tutorial/{step}.md'
            problems.append(f'{source} is missing: it is {role}')
            continue
        with open(os.path.join(root, source), encoding='utf-8') as f:
            problems += header_problems(f.read(), source)
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, 'examples', 'tutorial', step)):
            dirnames.sort()
            if 'shaders.json' in filenames:
                found = os.path.relpath(os.path.join(dirpath, 'shaders.json'), root).replace(os.sep, '/')
                problems.append(f'{found}: a Tour step cannot use shader packs')
    return problems


def main(argv):
    if argv != ['check']:
        print(__doc__, file=sys.stderr)
        return 2
    problems = step_problems(ROOT)
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
