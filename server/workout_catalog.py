"""Compile the source site's preserved workout sections into Coin's offline catalog.

Input is a directory of rendered HTML snapshots (basic-w1-d1.html, etc.).
Only source workout sections enter the coach; daily nutrition checklists do not.
Unspecified or ambiguous prescriptions remain athlete-advanced manual units.
No inference or network request runs during catalog load or a live workout.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin

BASE = 'https://boxing.dharmicdata.org'
VERSION = 'coin-workout-source-v1'

class Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []
    def has_class(self, name):
        return name in self.attrs.get('class', '').split()
    def descendants(self, predicate):
        for child in self.children:
            if isinstance(child, Node):
                if predicate(child):
                    yield child
                yield from child.descendants(predicate)
    def text(self):
        return ' '.join(child.text() if isinstance(child, Node) else child for child in self.children)

class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.root = Node()
        self.stack = [self.root]
    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in {'br','img','meta','link','input','hr','source','wbr','area','embed','param','col'}:
            self.stack.append(node)
    def handle_endtag(self, tag):
        for index in range(len(self.stack)-1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                break
    def handle_data(self, data):
        self.stack[-1].children.append(data)

TIMING = re.compile(r'\b(\d+)\s*ROUNDS?\s*OF\s*(\d+)\s*(MINUTES?|MINS?|SECONDS?|SECS?)\b', re.I)
REST = re.compile(r'\b(\d+)\s*(SECONDS?|SECS?|MINUTES?|MINS?)\s+OF\s+REST\b', re.I)
NEW_DRILL = re.compile(r'^(?:FR[O0]NTAL STANCE|FIGHTING ST[AN]*CE|BAG WORK|PARTNER WORK|VIRTUAL |LIGHT SPARRING|DRILLS WITH |CONDITIONING DRILL|MEDICINE BALL|MED BALL|STRETCHES|COOL[ -]DOWN|HAMMERS|PUNCHING UP|FREESTYLE (?:EXERCISES|SHADOW)|\d+\s+(?:KNUCKLE |JUMP |CLAP |MOUNTAIN )?(?:PUSH[ -]?UPS|SQUATS|BURPEES|CLIMBERS))', re.I)
EXERCISE = re.compile(r'PUSH[ -]?UPS|SQUATS|BURPEES|CLIMBERS|MEDICINE BALL|MED BALL|PLYOMETRIC|PPLYOMETRIC|TUCKS|LEG RAISES|JUMPS', re.I)


def normalize(text):
    return ' '.join(text.split()).strip()


def split_items(items):
    """Split only explicit drill starts after an existing timed prescription.

    Detailed combinations following a bag-round heading stay with that heading.
    Complex circuits remain intact rather than guessing how they repeat.
    """
    groups, current = [], []
    for item in items:
        text = item['text']
        prior = ' '.join(row['text'] for row in current)
        has_time = bool(TIMING.search(prior))
        if current and NEW_DRILL.match(text) and (has_time or re.match(r'CONDITIONING|STRETCHES|COOL[ -]DOWN', text, re.I)):
            groups.append(current)
            current = []
        current.append(item)
    if current:
        groups.append(current)
    return groups


def prescription(text):
    timings = list(TIMING.finditer(text))
    rests = list(REST.finditer(text))
    sets = re.findall(r'\b(\d+)\s*SETS?\b', text, re.I)
    reps = re.findall(r'\b(?:\d+(?:\s*[-–]\s*\d+)?|MAX)\s*(?:REPS?|TIMES)\b', text, re.I)
    result = {'completion': 'manual', 'rounds': None, 'durationSeconds': None,
              'restSeconds': None, 'sets': int(sets[0]) if len(sets)==1 else None,
              'reps': '; '.join(reps) or None, 'parseStatus':'manual_source_prescription'}
    # A mixed reps/circuit section must not disappear into a round timer.
    if len(timings) == 1 and not sets and not reps and not EXERCISE.search(text):
        match = timings[0]
        result.update(completion='timed', rounds=int(match[1]),
                      durationSeconds=int(match[2])*(60 if match[3].lower().startswith('min') else 1),
                      parseStatus='explicit_round_prescription')
        if len(rests) == 1:
            rest = rests[0]
            result['restSeconds'] = int(rest[1])*(60 if rest[2].lower().startswith('min') else 1)
        elif len(rests)>1 or re.search(r'\bREST\b', text, re.I):
            result.update(completion='manual', durationSeconds=None, rounds=None,
                          parseStatus='ambiguous_rest_prescription')
    return result


def compile_page(path):
    match = re.fullmatch(r'(basic|competitive)-w([1-5])-d([1-7])\.html', path.name)
    if not match:
        raise ValueError(f'Unexpected source filename: {path.name}')
    program, week, day = match.groups()
    raw = path.read_bytes()
    doc = Document()
    doc.feed(raw.decode('utf-8'))
    root = doc.root
    title = next((normalize(n.text()) for n in root.descendants(lambda n:n.tag=='h1')), f'Week {week} · Day {day}')
    source_url = f'{BASE}/program/{program}/week/{week}/day/{day}'
    lead_demo = next((n.attrs['href'] for n in root.descendants(lambda n:n.tag=='a')
                     if 'Lead demonstration' in n.text() and 'youtu' in n.attrs.get('href','')), None)
    pdf = next((urljoin(BASE,n.attrs['href']) for n in root.descendants(lambda n:n.tag=='a')
                if '/canonical/' in n.attrs.get('href','') and '.pdf' in n.attrs.get('href','')), None)
    sections = list(root.descendants(lambda n:n.has_class('workout-block')))
    blocks = []
    excluded = []
    exclusions = []
    source_count = 0
    for index, section in enumerate(sections):
        items = []
        for node in section.descendants(lambda n:n.has_class('source-block')):
            text = normalize(' '.join(child.text() for child in node.children if isinstance(child,Node)
                            and child.tag in {'h3','p','span'} and not child.has_class('source-marker')))
            urls = list(dict.fromkeys(urljoin(BASE,a.attrs['href']) for a in node.descendants(lambda n:n.tag=='a')
                        if 'youtu' in a.attrs.get('href','')))
            if lead_demo and any(node.descendants(lambda n:n.has_class('lead-reference'))):
                urls.append(lead_demo)
            if text:
                references = list(dict.fromkeys(urljoin(BASE,a.attrs['href']) for a in node.descendants(lambda n:n.tag=='a')
                                  if a.attrs.get('href','').startswith(('http','/'))))
                items.append({'id':node.attrs.get('id'), 'text':text, 'demoURLs':urls, 'referenceURLs':references})
        source_count += len(items)
        if not items:
            continue
        reason = None
        if section.has_class('workout-block--checklist'):
            reason = 'daily_lifestyle_checklist_outside_workout'
        elif section.has_class('workout-block--header') and len(items)==1 and re.match(r'^(?:BOXING WORKOUT|DAY)\b',items[0]['text'],re.I):
            reason = 'section_title_only'
        elif any(re.search(r'RECOVERY TIPS|TIPS FOR |BENEFITS OF BOXING|Hydration:|Eisenhower Matrix|MAXIMIZING YOUR DAY|Mental Relaxation:|Nutrition:', row['text'],re.I) for row in items) and not section.has_class('workout-block--header'):
            reason = 'general_advice_outside_workout'
        if reason:
            excluded.append(section.attrs.get('id'))
            exclusions.extend(dict(row,reason=reason) for row in items)
            continue
        kept=[]
        in_checklist=False
        for row in items:
            if re.match(r'DAILY\s+(?:TO DO|STRETCH)',row['text'],re.I):
                in_checklist=True
            if in_checklist:
                exclusions.append(dict(row,reason='embedded_daily_lifestyle_checklist'))
            elif re.match(r'^(?:DIG DEEPER!|YOU VS YOU|RECOVERY TIPS:|a healthy mind|Stay ready|never have to get ready|Champions|are made from something|inside them.a desire)',row['text'],re.I):
                exclusions.append(dict(row,reason='motivational_or_advice_heading'))
            else:
                kept.append(row)
        items=kept
        if not items:
            continue
        for subindex, group in enumerate(split_items(items)):
            full = '\n'.join(row['text'] for row in group)
            upper = full.upper()
            kind = ('exercise' if re.search(r'\b(?:SETS?|CIRCUITS?)\b',upper) else
                    'warmup' if 'WARM-UP' in upper or 'WARM UP' in upper else
                    'cooldown' if 'COOL-DOWN' in upper or 'COOL DOWN' in upper or full.upper().startswith('STRETCH') else
                    'recovery' if section.has_class('workout-block--recovery') else
                    'exercise' if EXERCISE.search(full) else 'boxing')
            block = {'id':f'{program}-w{week}-d{day}-{section.attrs.get("id",str(index))}-{subindex+1}',
                     'title':group[0]['text'], 'instructions':full, 'kind':kind,
                     'drillID':'free-boxing-v1' if kind=='boxing' else None,
                     'activityKey':None, 'sourceText':full, 'sourceSectionIndex':index+1,
                     'sourceSectionID':section.attrs.get('id'), 'sourceItems':group,
                     'sourceURL':source_url+'#'+section.attrs.get('id','workout'),
                     'referenceURLs':list(dict.fromkeys(u for row in group for u in row['referenceURLs'])),
                     'demoURLs':list(dict.fromkeys(u for row in group for u in row['demoURLs']))}
            block.update(prescription(full))
            blocks.append(block)
    if not blocks:
        raise ValueError(f'No workout source blocks in {path.name}')
    return {'id':f'{program}-w{week}-d{day}', 'program':program, 'week':int(week), 'day':int(day),
            'title':title, 'focus':'', 'sourceURL':source_url, 'sourcePDFURL':pdf,
            'sourceSHA256':hashlib.sha256(raw).hexdigest(), 'sourceSnapshot':path.name,
            'excludedSections':excluded, 'sourceExclusions':exclusions,
            'sourceItemCount':source_count, 'blocks':blocks}


def compile_catalog(source):
    workouts = [compile_page(path) for path in sorted(source.glob('*.html'))
                if re.fullmatch(r'(basic|competitive)-w[1-5]-d[1-7]\.html',path.name)]
    if len(workouts)!=70 or len({w['id'] for w in workouts})!=70:
        raise ValueError(f'Expected70 distinct source days, found {len(workouts)}')
    return {'schemaVersion':1, 'catalogVersion':VERSION, 'sourceURL':BASE,
            'sourceKind':'rendered_html_snapshot', 'workouts':workouts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    catalog=compile_catalog(args.source_dir)
    args.output.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    blocks=[b for w in catalog['workouts'] for b in w['blocks']]
    print(json.dumps({'days':len(catalog['workouts']),'blocks':len(blocks),
                      'timed':sum(b['completion']=='timed' for b in blocks),
                      'manual':sum(b['completion']=='manual' for b in blocks)}))
if __name__=='__main__':main()
