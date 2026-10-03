"""Checks the imported prescription contract, not model exercise accuracy."""
import json
import tempfile
import unittest
from pathlib import Path
from workout_catalog import prescription, compile_page, split_items

class PrescriptionTests(unittest.TestCase):
    def test_two_source_sections_split_at_distinct_prescriptions(self):
        cases = [
            ('competitive-w1-d1', 'p5-s3', [
                ('p5-b9', '10 PUSH-UPS; 6 360° JUMPS; 10 JUMP HALF SQUATS WITH PUNCHES'),
                ('p5-b10', 'FIGHTING STNCE: HIP AND SHOULDER ROTATION FOCUSED DRILL: 1'),
                ('p5-b11', 'ROUND OF 3 MINUTES'),
            ], [['p5-b9'], ['p5-b10', 'p5-b11']], ['manual', 'timed']),
            ('basic-w1-d5', 'p7-s6', [
                ('p7-b19', '6 ROUNDS OF 3 MINUTES OF BAG WORK'),
                ('p7-b20', 'Shadow ONLY boxing MOVEMENT with resistance bands. 6 rounds of 1 minute with 20'),
                ('p7-b21', 'sec of rest'),
                ('p7-b22', 'ONLY LONG RANGE ATTACKS'),
                ('p7-b23', 'ONLY CLOSE RANGE ATTACKS'),
                ('p7-b25', 'FREESTYLE'),
                ('p7-b26', 'CHANGE THE STACE'),
                ('p7-b28', 'CONDITIONING BAG WORK DRILL (1 ROUND)'),
            ], [['p7-b19'], ['p7-b20', 'p7-b21'], ['p7-b22', 'p7-b23', 'p7-b25', 'p7-b26'], ['p7-b28']],
             ['timed', 'timed', 'manual', 'manual']),
        ]
        for day, section, source, expected_ids, expected_completion in cases:
            rows = [{'id': ident, 'text': text} for ident, text in source]
            groups = split_items(rows, day, section)
            self.assertEqual([[row['id'] for row in group] for group in groups], expected_ids)
            self.assertEqual([prescription('\n'.join(row['text'] for row in group))['completion']
                              for group in groups], expected_completion)
            self.assertEqual([row for group in groups for row in group], rows)
            self.assertEqual(len(split_items(rows, 'other-w1-d1', section)), 1)

    def test_ambiguous_source_units_do_not_enable_exchange_routing(self):
        cases = [
            ('basic-w1-d5.html', 'p7-s6', [
                ('p7-b19', '6 ROUNDS OF 3 MINUTES OF BAG WORK'),
                ('p7-b20', 'Shadow ONLY boxing MOVEMENT with resistance bands. 6 rounds of 1 minute with 20'),
                ('p7-b21', 'sec of rest'),
                ('p7-b22', 'ONLY LONG RANGE ATTACKS'),
                ('p7-b28', 'CONDITIONING BAG WORK DRILL (1 ROUND)'),
            ], [('timed', 6, 180, 'boxing', 'free-boxing-v1'),
                ('timed', 6, 60, 'exercise', None),
                ('manual', None, None, 'exercise', None),
                ('manual', None, None, 'exercise', None)]),
            ('competitive-w1-d1.html', 'p5-s3', [
                ('p5-b9', '10 PUSH-UPS; 6 360° JUMPS; 10 JUMP HALF SQUATS WITH PUNCHES'),
                ('p5-b10', 'FIGHTING STNCE: HIP AND SHOULDER ROTATION FOCUSED DRILL: 1'),
                ('p5-b11', 'ROUND OF 3 MINUTES'),
            ], [('manual', None, None, 'exercise', None),
                ('timed', 1, 180, 'exercise', None)]),
        ]
        for filename, section, rows, expected in cases:
            markup = '<h1>Workout</h1><li class="workout-block" id="' + section + '">'
            markup += ''.join(f'<div class="source-block" id="{ident}"><h3>{text}</h3></div>'
                              for ident, text in rows)
            markup += '</li>'
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / filename
                path.write_text(markup)
                day = compile_page(path)
            actual = [(b['completion'], b['rounds'], b['durationSeconds'], b['kind'], b['drillID'])
                      for b in day['blocks']]
            self.assertEqual(actual, expected)
            self.assertEqual([r['id'] for b in day['blocks'] for r in b['sourceItems']],
                             [ident for ident, _ in rows])

    def test_explicit_rounds_and_rest(self):
        value = prescription('FRONTAL STANCE. 4 ROUNDS OF 2 MINUTES WITH 30 SECONDS OF REST IN BETWEEN.')
        self.assertEqual((value['rounds'],value['durationSeconds'],value['restSeconds']),(4,120,30))
    def test_no_rest_invented(self):
        value = prescription('1 ROUND OF 3 MINUTES')
        self.assertEqual(value['durationSeconds'],180)
        self.assertIsNone(value['restSeconds'])
    def test_standalone_duration_is_a_single_timer(self):
        value = prescription('CONDITIONING DRILL (4 MINUTES)')
        self.assertEqual((value['completion'], value['rounds'], value['durationSeconds']),
                         ('timed', 1, 240))
        self.assertEqual(prescription('CONDITIONING DRILL (1 ROUND)')['completion'], 'manual')
    def test_mixed_set_and_round_remain_manual(self):
        for text in ['BAG WORK. 6 ROUNDS OF 3 MINUTES. 2 SETS OF 15 REPS',
                     '1 ROUND OF 3 MINUTES. 20 PUSH-UPS',
                     '6 ROUNDS OF 3 MINUTES. THROW30 TIMES. REST FOR 30 SEC AND THROW15 TIMES',
                     '2 ROUND OF 1 MINUTE WITH 3O SECONDS OF REST IN BETWEEN']:
            self.assertEqual(prescription(text)['completion'],'manual',text)

class BundledCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((Path(__file__).parents[1]/'ios'/'WorkoutCatalog.json').read_text())
    def test_all_source_days(self):
        days=self.catalog['workouts']
        self.assertEqual(len(days),70)
        self.assertEqual({w['id'] for w in days},{f'{p}-w{w}-d{d}' for p in ['basic','competitive'] for w in range(1,6) for d in range(1,8)})
    def test_every_source_item_retained_and_traceable(self):
        for workout in self.catalog['workouts']:
            included=[row for block in workout['blocks'] for row in block['sourceItems']]
            accounted=included+workout['sourceExclusions']
            self.assertEqual(len(accounted),workout['sourceItemCount'])
            self.assertEqual(len({row['id'] for row in accounted}),workout['sourceItemCount'])
            self.assertEqual(len(workout['sourceSHA256']),64)
            self.assertTrue(workout['sourcePDFURL'].startswith('https://boxing.dharmicdata.org/canonical/'))
            for block in workout['blocks']:
                self.assertEqual(block['sourceText'],'\n'.join(row['text'] for row in block['sourceItems']))
                self.assertTrue(block['instructions'])
                self.assertNotIn('14 hour fast',block['instructions'])
                self.assertNotIn('1 gallon of water',block['instructions'])
                if block['completion']=='timed':
                    self.assertTrue(1<=block['rounds']<=100)
                    self.assertTrue(1<=block['durationSeconds']<=7200)
    def test_first_day_prescription_and_demo(self):
        day=next(w for w in self.catalog['workouts'] if w['id']=='basic-w1-d1')
        first=next(b for b in day['blocks'] if b['completion']=='timed')
        self.assertEqual((first['rounds'],first['durationSeconds'],first['restSeconds']),(4,120,30))
        self.assertTrue(first['demoURLs'])
        self.assertTrue(next(b for b in day['blocks'] if b['kind']=='warmup')['demoURLs'])
    def test_rest_day_preserved(self):
        day=next(w for w in self.catalog['workouts'] if w['id']=='basic-w1-d7')
        self.assertTrue(all(b['completion']=='manual' for b in day['blocks']))
        self.assertEqual(day['blocks'][0]['kind'],'recovery')
    def test_strength_and_endurance_inside_source_headers_are_preserved(self):
        day=next(w for w in self.catalog['workouts'] if w['id']=='basic-w1-d6')
        text='\n'.join(b['instructions'] for b in day['blocks'])
        self.assertIn('3 SETS OF 10 REPS EACH EXERCISE',text)
        self.assertIn('Pallof Press',text)
        self.assertIn('Dumbbell Overhead Walk (20 Steps Each)',text)
        day=next(w for w in self.catalog['workouts'] if w['id']=='competitive-w1-d6')
        self.assertIn('steady state run',day['blocks'][0]['instructions'])
        self.assertTrue(day['blocks'][0]['referenceURLs'])

    def test_reviewed_three_circuit_endurance_sources_remain_exact_and_traceable(self):
        exercises = ['Push-Up Shuttle', 'Squat With Med Ball Throws', 'Rolls', 'Plate Punches',
                     'Side Jumps', 'Plank', 'Landmine Punches', 'Boxing Steps With Weights',
                     'Wall Sit', 'Barbell Push-Outs']
        for lesson_id, page, number in [('competitive-w2-d6', 18, 2),
                                        ('competitive-w4-d6', 34, 4)]:
            day = next(w for w in self.catalog['workouts'] if w['id'] == lesson_id)
            self.assertEqual(len(day['blocks']), 1)
            block = day['blocks'][0]
            self.assertEqual(block['id'], f'{lesson_id}-p{page}-s1-1')
            self.assertEqual(block['completion'], 'manual')
            self.assertEqual([row['id'] for row in block['sourceItems']],
                             [f'p{page}-b{i}' for i in range(1, 16)])
            self.assertEqual([row['text'] for row in block['sourceItems']], [
                'WARM UP:', f'ENDURANCE WORKOUT #{number} WARM UP:',
                '3 CIRCUITS, 10 EXERCISES EACH. WORK FOR 1 MINUTE, REST FOR',
                '30 SECONDS. TAKE 2 MINUTES OF REST BETWEEN CIRCUITS',
                *exercises, 'Stretch Series'])
            self.assertTrue(all(row['demoURLs'] for row in block['sourceItems'][4:14]))
            self.assertEqual(block['sourceText'],
                             '\n'.join(row['text'] for row in block['sourceItems']))

if __name__=='__main__':unittest.main()
