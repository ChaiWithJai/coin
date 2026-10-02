"""Checks the imported prescription contract, not model exercise accuracy."""
import json
import unittest
from pathlib import Path
from workout_catalog import prescription, compile_page

class PrescriptionTests(unittest.TestCase):
    def test_explicit_rounds_and_rest(self):
        value = prescription('FRONTAL STANCE. 4 ROUNDS OF 2 MINUTES WITH 30 SECONDS OF REST IN BETWEEN.')
        self.assertEqual((value['rounds'],value['durationSeconds'],value['restSeconds']),(4,120,30))
    def test_no_rest_invented(self):
        value = prescription('1 ROUND OF 3 MINUTES')
        self.assertEqual(value['durationSeconds'],180)
        self.assertIsNone(value['restSeconds'])
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

if __name__=='__main__':unittest.main()
