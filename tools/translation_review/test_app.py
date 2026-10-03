import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from app import atomic_write, item_key, load_labels, load_source


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'proposal.json'
        text = '10 JUMP SQUATS'
        self.item = {'blockID': 'block', 'sourceItemID': 'item', 'sourceText': text,
                     'sourceTextSHA256': hashlib.sha256(text.encode()).hexdigest(),
                     'proposedFrench': '10 squats sautés'}
        self.source = {'purpose': 'translation_proposals_only', 'runtimeEligible': False,
                       'jobID': 'job', 'sourceSHA256': 'snapshot', 'items': [self.item]}
        self.path.write_text(json.dumps(self.source))

    def tearDown(self):
        self.tmp.cleanup()

    def test_load_and_local_labels(self):
        source = load_source(self.path)
        self.assertEqual(item_key(source['items'][0]), 'block::item')
        labels_path = self.path.with_name('review.json')
        labels = load_labels(labels_path, source)
        labels['labels']['block::item'] = {'decision': 'fail', 'notes': 'wrong term'}
        atomic_write(labels_path, labels)
        self.assertEqual(load_labels(labels_path, source)['labels']['block::item']['decision'], 'fail')
        self.assertFalse(load_labels(labels_path, source)['runtimeEligible'])

    def test_source_drift_rejected(self):
        self.source['items'][0]['sourceText'] = 'changed'
        self.path.write_text(json.dumps(self.source))
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            load_source(self.path)

    def test_cross_job_labels_rejected(self):
        source = load_source(self.path)
        labels = load_labels(self.path.with_name('review.json'), source)
        labels['jobID'] = 'other'
        labels_path = self.path.with_name('review.json')
        atomic_write(labels_path, labels)
        with self.assertRaisesRegex(ValueError, 'do not belong'):
            load_labels(labels_path, source)


if __name__ == '__main__':
    unittest.main()
