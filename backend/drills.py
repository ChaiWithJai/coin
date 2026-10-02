"""Versioned prototype drill text. Analyst-authored, not coach-validated."""
import unicodedata
VERSION='prototype-library-v1'
DRILLS={
 'guard_return':{
  'fr':'Au ralenti, fais un jab isolé en gardant la main arrière près du visage. Reviens à ta garde de départ avant de recommencer. Vérifie ce point avec ton coach.',
  'en':'Slowly throw one jab while keeping your rear hand near your face. Return to your starting guard before repeating. Check this focus with your coach.'},
 'review_clip':{
  'fr':'Revois ce passage au ralenti et note ce qui est clairement visible. Choisis avec ton coach un seul point à travailler avant de modifier ta technique.',
  'en':'Replay this moment slowly and note what is clearly visible. Choose one focus with your coach before changing your technique.'}}
def eligible(text):
 text=''.join(c for c in unicodedata.normalize('NFKD',text.lower()) if not unicodedata.combining(c))
 result=['review_clip']
 if ('rear hand' in text or 'main arriere' in text) and ('low' in text or 'basse' in text):result.append('guard_return')
 return result

def render_selection(notes,index,drill_id,language):
 if type(index) is not int or not 0<=index<len(notes):raise ValueError('Invalid observation index')
 if language not in ('fr','en'):raise ValueError('Unsupported language')
 note=notes[index]
 if drill_id not in eligible(note['text']):raise ValueError('Drill not eligible for this note')
 return {'observation':note['text'],'clip_timestamp_seconds':note['seconds'],'drill':DRILLS[drill_id][language],
         'limitation': 'Suggestion fondée sur tes notes, sans analyse automatique de la vidéo. À confirmer avec ton coach.' if language=='fr' else 'Suggestion based on your notes, without automatic video analysis. Confirm it with your coach.',
         'drill_id':drill_id,'drill_library_version':VERSION}
