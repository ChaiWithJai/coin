import unittest
from unittest.mock import patch
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import round_harness as harness

class ContextualReportTests(unittest.TestCase):
    def test_free_round_does_not_inherit_drill_faults(self):
        summary={'language':'en','stance':'orthodox','drill_id':'free-boxing-v1','workout_mode':'freestyle','round':1,'duration_s':180,
                 'exchanges':[{'id':1,'punches':[{'hand':'rear','atMs':1000}],'resetMs':None}]}
        with patch.object(harness,'_post',return_value={'model':'actual-9b','choices':[{'message':{'content':'{"interpretation":"Counts describe activity, not form."}'}}]}) as call:
            response,stages,facts=harness.run(summary)
        self.assertEqual(response['models'],['actual-9b'])
        self.assertEqual(response['labels'],[])
        self.assertFalse(facts['quality_evaluated'])
        self.assertNotIn('fault_counts',facts)
        self.assertEqual(call.call_count,1)
        self.assertNotIn('jab',response['constraint'])

    def test_program_keeps_source_context_and_language(self):
        summary={'language':'fr','stance':'orthodox','drill_id':'free-boxing-v1','workout_mode':'program',
                 'source_title':'Stance drill','source_instructions':'4 rounds of2minutes','round':1,'duration_s':120,'exchanges':[]}
        with patch.object(harness,'_post',return_value={'choices':[{'message':{'content':'{"interpretation":"La technique reste à vérifier."}'}}]}) as call:
            response,stages,facts=harness.run(summary)
        self.assertEqual(response['drill'],'Stance drill')
        self.assertIn('programme',response['constraint'])
        self.assertIn('French',call.call_args.args[1]['messages'][0]['content'])
        self.assertIn('Stance drill',call.call_args.args[1]['messages'][1]['content'])
        self.assertEqual(response['models'],['unreported-model'])

if __name__=='__main__':unittest.main()
