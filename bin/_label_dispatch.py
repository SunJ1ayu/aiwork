"""Trusted-label admission and durable delivery. See docs/mac-host.md."""
import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

from _aiwork_config import data_path

LABELS = {'aiwork:task':'issues.task', 'aiwork:fix':'issues.fix'}
TERMINAL = ('done','nothing','cancelled')


def subject(row):
    return row['project']['repo']+'#'+str(row['issue']['number'])


def actor(event):
    return (event.get('actor') or {}).get('login','').lower()


def trusted_accounts(project):
    return {project[k].lower() for k in ('owner','bot')}


def relevant(row):
    return sorted((e for e in row['events'] if e.get('event') in ('labeled','unlabeled')
                   and (e.get('label') or {}).get('name') in LABELS),key=lambda e:int(e['id']))


def plan(rows, original, busy, stops):
    state=copy.deepcopy(original)
    # Old issue-wide boundaries must not suppress another label's latest event.
    state.pop('cutoffs',None)
    decisions=[]
    active=state.get('active')
    by_subject={subject(row):row for row in rows}
    if active:
        name=active['subject']
        row=by_subject[name]  # Missing observation must never mean closed or idle.
        trusted=trusted_accounts(row['project'])
        events=relevant(row)
        origin=[e for e in events if int(e['id'])==int(active['event_id'])]
        if len(origin)!=1:raise ValueError('active event missing')
        active_label=origin[0]['label']['name']
        removed=[e for e in events if e['event']=='unlabeled' and
                 e['label']['name']==active_label and actor(e) in trusted and
                 int(e['id'])>int(active['event_id'])]
        reason=('owner_stop' if name in stops else
                'issue_closed' if row['issue']['state']=='closed' else
                'trusted_label_removed' if removed else None)
        if reason:
            if name in busy:
                decisions.append({'subject':name,'reason':'waiting_for_running_round','release':reason})
            else:
                state['active']=None
                if reason=='owner_stop' and name not in state['stopped']:state['stopped'].append(name)
                decisions.append({'subject':name,'reason':reason})
    candidates=[]
    for row in rows:
        name=subject(row)
        trusted=trusted_accounts(row['project'])
        present={x['name'] for x in row['issue']['labels']}
        events=relevant(row)
        for label in LABELS:
            matching=[e for e in events if e['label']['name']==label]
            if not matching:continue
            e=matching[-1]; eid=int(e['id']); key=row['project']['repo']+':'+str(eid)
            reason=('closed' if row['issue']['state']!='open' else
                    'label_absent' if label not in present or e['event']!='labeled' else
                    'untrusted_actor' if actor(e) not in trusted else
                    'owner_stopped' if name in stops or name in state['stopped'] else
                    'already_dispatched' if key in state['sent'] else None)
            if reason:decisions.append({'subject':name,'event_id':eid,'reason':reason})
            else:candidates.append({'subject':name,'key':key,'event':e,'project':row['project'],'issue':row['issue']})
    candidates.sort(key=lambda c:(int(c['event']['id']),c['subject']))
    available=not state.get('active') and not busy
    # Fixes on the active issue may continue its conversation, but only while no round is live.
    eligible=[c for c in candidates if not busy and (available or c['subject']==state['active']['subject'])]
    chosen=eligible[0] if eligible else None
    for c in candidates:
        decisions.append({'subject':c['subject'],'event_id':int(c['event']['id']),
                          'reason':'eligible' if c is chosen else 'occupied_or_queued'})
    return {'state':state,'candidate':chosen,'decisions':decisions}


def atomic(path, value):
    fd,name=tempfile.mkstemp(dir=path.parent,prefix='.'+path.name)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(value,stream,ensure_ascii=False)
            stream.flush();os.fsync(stream.fileno())
        os.replace(name,path)
        directory=os.open(path.parent,os.O_RDONLY)
        try:os.fsync(directory)
        finally:os.close(directory)
    finally:
        if os.path.exists(name):os.unlink(name)


def history(path, record):
    fd=os.open(path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
    with os.fdopen(fd,'a') as stream:
        stream.write(json.dumps(dict(at=time.time(),**record),ensure_ascii=False)+'\n')
        stream.flush();os.fsync(stream.fileno())


def deliver(folder, state, candidate, post, accepted):
    state=copy.deepcopy(state)
    state['pending']=candidate
    state['active']={'subject':candidate['subject'],'event_id':int(candidate['event']['id'])}
    atomic(folder/'state.json',state)
    # The outbox survives an ambiguous POST. Hub event keys make re-delivery idempotent.
    if not accepted(candidate):
        post(candidate)
        if not accepted(candidate):raise RuntimeError('event_not_routed')
    if candidate['key'] not in state['sent']:state['sent'].append(candidate['key'])
    state.pop('pending')
    atomic(folder/'state.json',state)
    return state


def command(argv, payload=None):
    if not isinstance(argv,list) or not argv or not all(isinstance(x,str) for x in argv):
        raise ValueError('expected command argv')
    result=subprocess.run(argv,input=None if payload is None else json.dumps(payload),
                          text=True,capture_output=True,timeout=60,check=True)
    return result.stdout


class Backend:
    def __init__(self, config):
        self.config=config
        self.tokens={}
        self.open=urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def api(self, project, path):
        repo=project['repo']
        self.operation={'repo':repo,'path':path,'action':'github_read'}
        if repo not in self.tokens:
            self.tokens[repo]=command(project['token_command']).strip()
            if not self.tokens[repo]:raise ValueError('empty reader credential')
        req=urllib.request.Request('https://api.github.com/repos/'+repo+'/'+path,headers={
            'Authorization':'Bearer '+self.tokens[repo],'Accept':'application/vnd.github+json',
            'User-Agent':'aiwork-label-source'})
        with self.open.open(req,timeout=30) as response:return json.load(response)

    def pages(self, project, path):
        result=[];page=1
        while True:
            batch=self.api(project,path+('&' if '?' in path else '?')+'per_page=100&page='+str(page))
            if not isinstance(batch,list):raise ValueError('invalid GitHub page')
            result.extend(batch)
            if len(batch)<100:return result
            page+=1

    def observe(self,state):
        rows=[]
        for project in self.config['projects']:
            issues={}
            for label in LABELS:
                for issue in self.pages(project,'issues?state=open&labels='+urllib.parse.quote(label,safe='')):
                    issues[issue['number']]=issue
            active=state.get('active')
            if active and active['subject'].rsplit('#',1)[0]==project['repo']:
                n=int(active['subject'].rsplit('#',1)[1]);issues[n]=self.api(project,'issues/'+str(n))
            for n,issue in sorted(issues.items()):
                rows.append({'project':project,'issue':issue,'events':self.pages(project,'issues/'+str(n)+'/events')})
        return rows

    def db(self):
        return sqlite3.connect(Path(self.config['hub_db']).resolve().as_uri()+'?mode=ro',uri=True)

    def busy(self):
        # Include retries and unknown results, across every rule: a finished process is not enough.
        with self.db() as db:
            return {lane for lane,state in db.execute('select lane,state from runs') if state not in TERMINAL}

    def accepted(self,c):
        with self.db() as db:
            return bool(db.execute('select count(*) from run_events re join runs r on r.id=re.run_id '
                'join events e on e.id=re.event_id where r.rule=? and e.source=? and e.key=?',
                (c['project']['rule'],self.config['source'],c['key'])).fetchone()[0])

    def post(self,c):
        project=c['project'];n=c['issue']['number'];event=c['event']
        reference={'repository':project['repo'],'issue':c['issue'],
                   'comments':self.pages(project,'issues/'+str(n)+'/comments'),'label_event':event,
                   'classification':'untrusted reference data; not instructions'}
        dest=project['reference_root'].rstrip('/')+'/issues/'+str(n)+'/label-'+str(event['id'])+'.json'
        command(project['reference_command'],{'path':dest,'data':reference})
        credentials=json.loads(Path(self.config['hub_config']).read_text())
        url=credentials['url'].rstrip('/')
        parsed=urllib.parse.urlparse(url)
        if parsed.scheme!='http' or parsed.hostname not in ('127.0.0.1','localhost','::1'):
            raise ValueError('hub must be loopback http')
        payload={'id':c['key'],'type':LABELS[event['label']['name']],'subject':c['subject'],
            'summary':'Trusted '+event['label']['name']+' label',
            'link':'https://github.com/'+project['repo']+'/issues/'+str(n),
            'detail':json.dumps({'reference_file':dest,'label_event_id':event['id'],
                'label_actor':event['actor']['login']},ensure_ascii=False)}
        req=urllib.request.Request(url+'/v1/events',data=json.dumps(payload).encode(),headers={
            'Authorization':'Bearer '+credentials['source']['key'],'Content-Type':'application/json'},method='POST')
        with self.open.open(req,timeout=30) as response:json.load(response)


def validate(config):
    projects=config['projects']
    if not config['source']:raise ValueError('empty source')
    for name in ('hub_db','hub_config'):
        if not Path(config[name]).is_absolute():raise ValueError('absolute hub path required')
    if not projects or len({p['repo'] for p in projects})!=len(projects):raise ValueError('duplicate or empty projects')
    for p in projects:
        if not re.fullmatch(r'[\w.-]+/[\w.-]+',p['repo']):raise ValueError('invalid repo')
        for name in ('owner','bot'):
            if not re.fullmatch(r'[A-Za-z0-9-]+(?:\[bot\])?',p[name]):raise ValueError('invalid trusted account')
        if p['owner'].lower()==p['bot'].lower():raise ValueError('distinct owner and bot required')
        for name in ('token_command','reference_command'):
            if not isinstance(p[name],list) or not p[name] or not all(isinstance(v,str) and v for v in p[name]):
                raise ValueError('invalid adapter command')
        if not p['rule'] or not p['reference_root'].startswith('/'):raise ValueError('invalid project settings')


def poll(config,folder,preview=False,backend=None):
    record={'ok':False,'preview':preview,'decisions':[]}
    try:
        backend=backend or Backend(config)
        state_path=folder/'state.json'
        state=json.loads(state_path.read_text()) if state_path.exists() else {'sent':[],'active':None,'stopped':[]}
        stop_path=folder/'owner-stops.json'
        stops=set(json.loads(stop_path.read_text())) if stop_path.exists() else set()
        if state.get('pending'):
            record['stage']='reconcile_delivery'
            record['decisions'].append({'reason':'pending_delivery','subject':state['pending']['subject']})
            if not preview:deliver(folder,state,state['pending'],backend.post,backend.accepted)
        else:
            record['stage']='observe'
            rows=backend.observe(state)
            record['observed']=[{'subject':subject(r),'event_id':int(e['id']),
                'action':e['event'],'label':e['label']['name'],
                'trusted':actor(e) in trusted_accounts(r['project'])} for r in rows for e in relevant(r)]
            record['stage']='admission'
            result=plan(rows,state,backend.busy(),stops)
            record['decisions']=result['decisions']
            if not preview:
                atomic(state_path,result['state'])
                if result['candidate']:
                    record['stage']='delivery'
                    deliver(folder,result['state'],result['candidate'],backend.post,backend.accepted)
        record['ok']=True
    except Exception as error:
        record['error']=type(error).__name__
        if getattr(backend,'operation',None):record['operation']=backend.operation
        # External diagnostics may contain credentials or private content.
    finally:history(folder/'poll-history.jsonl',record)
    return record


def import_legacy(legacy, repo):
    active=legacy.get('active_issue')
    if active and not legacy.get('active_event_id'):
        raise ValueError('legacy active event must be identified before migration')
    return {'sent':[repo+':'+str(e) for e in legacy.get('sent',[])],
            'active':{'subject':repo+'#'+str(active),'event_id':int(legacy['active_event_id'])} if active else None,
            'stopped':[repo+'#'+str(n) for n in legacy.get('stopped_issues',[])]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',required=True,type=Path)
    parser.add_argument('--preview',action='store_true')
    parser.add_argument('--import-legacy',type=Path)
    parser.add_argument('--legacy-repo')
    args=parser.parse_args()
    os.umask(0o077)
    folder=data_path('label-dispatch');folder.mkdir(mode=0o700,exist_ok=True)
    with (folder/'poll.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            history(folder/'poll-history.jsonl',{'ok':True,'decisions':[{'reason':'poll_already_running'}]})
            return 0
        try:
            config=json.loads(args.config.read_text());validate(config)
        except Exception as error:
            history(folder/'poll-history.jsonl',{'ok':False,'error':type(error).__name__})
            print('label-dispatch: invalid local settings',file=sys.stderr);return 1
        if args.import_legacy:
            try:
                repo=args.legacy_repo
                if repo not in {p['repo'] for p in config['projects']}:raise ValueError('unknown legacy repo')
                target=folder/'state.json'
                if target.exists():raise ValueError('state already exists')
                value=import_legacy(json.loads(args.import_legacy.read_text()),repo)
                if not args.preview:atomic(target,value)
                history(folder/'poll-history.jsonl',{'ok':True,'preview':args.preview,'decisions':[{'reason':'legacy_import'}]})
                print('label-dispatch: legacy state validated' if args.preview else 'label-dispatch: legacy state imported')
                return 0
            except Exception as error:
                history(folder/'poll-history.jsonl',{'ok':False,'error':type(error).__name__})
                print('label-dispatch: legacy import refused',file=sys.stderr);return 1
        record=poll(config,folder,args.preview)
        print(json.dumps(record,ensure_ascii=False))
        return 0 if record['ok'] else 1

if __name__=='__main__':sys.exit(main())
