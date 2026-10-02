"""Import an explicitly supplied local app index. No footage or note text is uploaded.
All decisions remain unapproved for training until independent label review.
"""
import argparse,json
from pathlib import Path
import mlflow

def records(index):
    seen=set()
    for session in index:
        for label in session.get('guardLabels') or []:
            if label['sessionID'] != session['id']:raise ValueError('Session mismatch')
            if label['id'] in seen:raise ValueError('Duplicate label ID')
            seen.add(label['id'])
            yield {**label,'eligibleForTraining':False,'review_status':'pending_independent_review'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('index',type=Path);args=parser.parse_args()
    labels=list(records(json.loads(args.index.read_text())))
    mlflow.set_tracking_uri('http://127.0.0.1:5210');experiment=mlflow.set_experiment('boxing-app-trajectory')
    client=mlflow.MlflowClient();count=0
    for label in labels:
        import uuid
        identity=str(uuid.UUID(label['id']))
        if client.search_runs([experiment.experiment_id],filter_string=f"tags.guard_label_id = '{identity}' and attributes.status = 'FINISHED'",max_results=1):continue
        with mlflow.start_run(run_name='guard-label',tags={'guard_label_id':identity,'session_id':label['sessionID'],'record_kind':'unreviewed_label','training_eligible':'false'}):
            mlflow.log_dict(label,'label.json')
        count+=1
    print(json.dumps({'imported':count,'available':len(labels),'training_eligible':0}))
if __name__=='__main__':main()
