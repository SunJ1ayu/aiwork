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
from typing import NamedTuple
import urllib.parse
import urllib.request

from _aiwork_config import builder_roles, data_path

LABELS = {'aiwork:task': 'issues.task', 'aiwork:fix': 'issues.fix'}
LABELS.update({
    f'{label}:{family}': f'{event_type}.{family}'
    for label, event_type in LABELS.items()
    for family in builder_roles()
})
TERMINAL = ('done','nothing','cancelled')
DEFAULT_MAX_ACTIVE = 1


def capacity(config):
    """Local label-source JSON: max_active is a positive integer; omission preserves the old limit.

    Invalid or unreadable settings stop admission; they never fall back to extra capacity.
    The limit counts the union of durable issue slots and nonterminal hub lanes.
    Configured dispatch rules use issue subjects as parallel lanes; other rules
    count separately by (rule, lane), even when their lane equals an issue.
    Empty lanes (serial rules) stop admission and release: their subject is unknown.
    Protocol source: agent-autoloop v1.6.1 kernel/decide.ts enqueue and route.
    Lowering it keeps existing slots and queues new issues until occupancy drops.
    """
    value = config.get('max_active', DEFAULT_MAX_ACTIVE)
    if type(value) is not int or value <= 0:
        raise ValueError('max_active must be a positive integer')
    return value


def upgraded(original):
    """Copy old singleton slots/outbox into per-subject maps without losing delivery history."""
    state = copy.deepcopy(original)
    version = state.get('version', 1)
    if version not in (1, 2):
        raise ValueError('unsupported dispatch state')
    if version == 1:
        for field in ('active', 'pending'):
            entry = state.get(field)
            state[field] = {entry['subject']: entry} if entry else {}
        state['version'] = 2
    for field in ('active', 'pending'):
        if not isinstance(state[field], dict):
            raise ValueError('invalid dispatch slots')
        for name, entry in state[field].items():
            if entry['subject'] != name:
                raise ValueError('invalid dispatch subject')
    for name, entry in state['pending'].items():
        if state['active'][name]['event_id'] != int(entry['event']['id']):
            raise ValueError('pending delivery requires its slot')
    state.pop('cutoffs', None)
    return state


SUBJECT_SEPARATOR = '#'
FILES = {'state':'state.json', 'stops':'owner-stops.json',
         'history':'poll-history.jsonl', 'lock':'poll.lock'}
EVENT_SEPARATOR = ':'
ISSUES_ROUTE = 'issues'
EVENTS_SUFFIX = '/events'
COMMENTS_SUFFIX = '/comments'
REFERENCE_LABEL_PREFIX = 'label-'
REFERENCE_SUFFIX = '.json'
HUB_EVENTS_ROUTE = '/v1/events'


class Reason:
    OWNER_STOP = 'owner_stop'
    ISSUE_CLOSED = 'issue_closed'
    LABEL_REMOVED = 'trusted_label_removed'
    WAITING = 'waiting_for_running_round'
    CLOSED = 'closed'
    LABEL_ABSENT = 'label_absent'
    UNTRUSTED = 'untrusted_actor'
    UNROUTED = 'builder_route_missing'
    CONFLICT = 'conflicting_dispatch_labels'
    STOPPED = 'owner_stopped'
    SENT = 'already_dispatched'
    ELIGIBLE = 'eligible'
    QUEUED = 'occupied_or_queued'
    PENDING = 'pending_delivery'
    LOCKED = 'poll_already_running'
    IMPORTED = 'legacy_import'


class Release(NamedTuple):
    reason: str
    persist_stop: bool = False


def local_files(folder):
    return {role:folder/name for role,name in FILES.items()}


def issue_subject(repo, number):
    return SUBJECT_SEPARATOR.join((repo,str(number)))


def split_subject(value):
    repo,number=value.rsplit(SUBJECT_SEPARATOR,1)
    return repo,int(number)


def event_key(repo, event_id):
    return EVENT_SEPARATOR.join((repo,str(event_id)))


def issue_path(number, suffix=''):
    return ISSUES_ROUTE+'/'+str(number)+suffix


def subject(row):
    return issue_subject(row['project']['repo'],row['issue']['number'])


def actor(event):
    return (event.get('actor') or {}).get('login','').lower()


def trusted_accounts(project):
    return {project[k].lower() for k in ('owner','bot')}


def label_route(project, label):
    parts = label.split(':', 2)
    if len(parts) == 2:
        return project['rule']
    return project.get('builder_rules', {}).get(parts[2])


def label_kind(label):
    parts = label.split(':', 2)
    base = ':'.join(parts[:2])
    return base if base in LABELS and (len(parts) == 2 or parts[2]) else None


def relevant(row):
    return sorted((e for e in row['events'] if e.get('event') in ('labeled','unlabeled')
                   and label_kind((e.get('label') or {}).get('name', ''))),key=lambda e:int(e['id']))


def plan(rows, original, busy, stops, max_active=DEFAULT_MAX_ACTIVE):
    capacity({'max_active': max_active})
    state=upgraded(original)
    decisions=[]
    blocked=set()
    active=state.get('active')
    by_subject={subject(row):row for row in rows}
    for name, slot in list(active.items()):
        if name in state['pending']:
            continue  # An ambiguous delivery cannot be released or overtaken.
        row=by_subject.get(name)
        if row is None:
            blocked.add(name)
            decisions.append({'subject':name,'reason':'active_observation_missing'})
            continue  # Missing observation must never mean closed or idle.
        trusted=trusted_accounts(row['project'])
        events=relevant(row)
        origin=[e for e in events if int(e['id'])==int(slot['event_id'])]
        if len(origin)!=1:
            blocked.add(name)
            decisions.append({'subject':name,'reason':'active_event_missing'})
            continue
        active_label=origin[0]['label']['name']
        removed=[e for e in events if e['event']=='unlabeled' and
                 e['label']['name']==active_label and actor(e) in trusted and
                 int(e['id'])>int(slot['event_id'])]
        release=(Release(Reason.OWNER_STOP,True) if name in stops else
                 Release(Reason.ISSUE_CLOSED) if row['issue']['state']=='closed' else
                 Release(Reason.LABEL_REMOVED) if removed else None)
        if release:
            if name in busy:
                decisions.append({'subject':name,'reason':Reason.WAITING,'release':release.reason})
            else:
                del active[name]
                if release.persist_stop and name not in state['stopped']:state['stopped'].append(name)
                decisions.append({'subject':name,'reason':release.reason})
    candidates=[]
    for row in rows:
        name=subject(row)
        trusted=trusted_accounts(row['project'])
        present={x['name'] for x in row['issue']['labels']}
        events=relevant(row)
        kinds = {}
        for label in sorted({e['label']['name'] for e in events}):
            matching=[e for e in events if e['label']['name']==label]
            e=matching[-1]; eid=int(e['id']); key=event_key(row['project']['repo'],eid)
            reason=(Reason.CLOSED if row['issue']['state']!='open' else
                    Reason.LABEL_ABSENT if label not in present or e['event']!='labeled' else
                    Reason.UNTRUSTED if actor(e) not in trusted else
                    Reason.UNROUTED if not label_route(row['project'], label) else None)
            if reason:
                decisions.append({'subject':name,'event_id':eid,'reason':reason})
            else:
                kinds.setdefault(label_kind(label), []).append((e, key))
        # Only trusted, present, routed labels can compete for the same dispatch.
        for group in kinds.values():
            for e, key in group:
                reason=(Reason.CONFLICT if len(group) > 1 else
                        Reason.STOPPED if name in stops or name in state['stopped'] else
                        Reason.SENT if key in state['sent'] else None)
                if reason:decisions.append({'subject':name,'event_id':int(e['id']),'reason':reason})
                else:candidates.append({'subject':name,'key':key,'event':e,'project':row['project'],'issue':row['issue']})
    candidates.sort(key=lambda c:(int(c['event']['id']),c['subject']))
    occupied=set(active) | set(busy)
    # Continuations reuse their issue's slot, independently of other live lanes.
    eligible=[c for c in candidates if c['subject'] not in busy and c['subject'] not in blocked
              and c['subject'] not in state['pending']
              and (c['subject'] in active or len(occupied) < max_active)]
    chosen=eligible[0] if eligible else None
    for c in candidates:
        decisions.append({'subject':c['subject'],'event_id':int(c['event']['id']),
                          'reason':Reason.ELIGIBLE if c is chosen else Reason.QUEUED})
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
    state=upgraded(state)
    name=candidate['subject']
    state['pending'][name]=candidate
    state['active'][name]={'subject':name,'event_id':int(candidate['event']['id'])}
    atomic(local_files(folder)['state'],state)
    # The outbox survives an ambiguous POST. Hub event keys make re-delivery idempotent.
    if not accepted(candidate):
        post(candidate)
        if not accepted(candidate):raise RuntimeError('event_not_routed')
    if candidate['key'] not in state['sent']:state['sent'].append(candidate['key'])
    del state['pending'][name]
    atomic(local_files(folder)['state'],state)
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
            # Discover labels independently of configured routes, including misspelled families.
            for issue in self.pages(project, ISSUES_ROUTE + '?state=open'):
                if any(label_kind(label['name']) for label in issue['labels']):
                    issues[issue['number']] = issue
            for active in upgraded(state)['active'].values():
                repo,n=split_subject(active['subject'])
                if repo==project['repo']:
                    try: issues[n]=self.api(project,issue_path(n))
                    except Exception: continue  # The retained slot is reported by plan.
            for n,issue in sorted(issues.items()):
                try: events=self.pages(project,issue_path(n,EVENTS_SUFFIX))
                except Exception: continue  # Missing observation cannot release a slot.
                rows.append({'project':project,'issue':issue,'events':events})
        return rows

    def db(self):
        return sqlite3.connect(Path(self.config['hub_db']).resolve().as_uri()+'?mode=ro',uri=True)

    def busy(self):
        # Include retries and unknown results, across every rule: a finished process is not enough.
        # v1.6.1 kernel/decide.ts enqueue uses subject only for parallel rules;
        # serial rules have an empty lane. Never interpret that as idle.
        routes = {route for project in self.config.get('projects', [])
                  for route in (project['rule'], *project.get('builder_rules', {}).values())}
        with self.db() as db:
            running = [(rule, lane) for rule, lane, state in
                       db.execute('select rule,lane,state from runs') if state not in TERMINAL]
        if any(not lane for rule, lane in running):
            raise ValueError('hub_lane_unmapped')
        return {lane if rule in routes else ('other_rule', rule, lane)
                for rule, lane in running}

    def accepted(self,c):
        with self.db() as db:
            return bool(db.execute('select count(*) from run_events re join runs r on r.id=re.run_id '
                'join events e on e.id=re.event_id where r.rule=? and e.source=? and e.key=?',
                (label_route(c['project'], c['event']['label']['name']),self.config['source'],c['key'])).fetchone()[0])

    def post(self,c):
        project=c['project'];n=c['issue']['number'];event=c['event']
        reference={'repository':project['repo'],'issue':c['issue'],
                   'comments':self.pages(project,issue_path(n,COMMENTS_SUFFIX)),'label_event':event,
                   'classification':'untrusted reference data; not instructions'}
        dest=project['reference_root'].rstrip('/')+'/'+issue_path(n)+'/'+REFERENCE_LABEL_PREFIX+str(event['id'])+REFERENCE_SUFFIX
        command(project['reference_command'],{'path':dest,'data':reference})
        credentials=json.loads(Path(self.config['hub_config']).read_text())
        url=credentials['url'].rstrip('/')
        parsed=urllib.parse.urlparse(url)
        if parsed.scheme!='http' or parsed.hostname not in ('127.0.0.1','localhost','::1'):
            raise ValueError('hub must be loopback http')
        payload={'id':c['key'],'type':LABELS[event['label']['name']],'subject':c['subject'],
            'summary':'Trusted '+event['label']['name']+' label',
            'link':'https://github.com/'+project['repo']+'/'+issue_path(n),
            'detail':json.dumps({'reference_file':dest,'label_event_id':event['id'],
                'label_actor':event['actor']['login']},ensure_ascii=False)}
        req=urllib.request.Request(url+HUB_EVENTS_ROUTE,data=json.dumps(payload).encode(),headers={
            'Authorization':'Bearer '+credentials['source']['key'],'Content-Type':'application/json'},method='POST')
        with self.open.open(req,timeout=30) as response:json.load(response)


def validate(config):
    capacity(config)
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
        rules = p.get('builder_rules', {})
        if not isinstance(rules, dict) or not rules.keys() <= builder_roles().keys():
            raise ValueError('invalid builder rules')
        routes = [p['rule'], *rules.values()]
        if (not all(isinstance(rule, str) and rule.strip() for rule in routes)
                or len(set(routes)) != len(routes) or not p['reference_root'].startswith('/')):
            raise ValueError('invalid project settings')


def poll(config,folder,preview=False,backend=None):
    record={'ok':False,'preview':preview,'decisions':[]}
    try:
        backend=backend or Backend(config)
        state_path=local_files(folder)['state']
        state=json.loads(state_path.read_text()) if state_path.exists() else {'sent':[],'active':None,'stopped':[]}
        stop_path=local_files(folder)['stops']
        stops=set(json.loads(stop_path.read_text())) if stop_path.exists() else set()
        limit=capacity(config)
        state=upgraded(state)
        errors=[]
        had_pending=bool(state['pending'])
        for name, candidate in list(state['pending'].items()):
            record['stage']='reconcile_delivery'
            record['decisions'].append({'reason':Reason.PENDING,'subject':name})
            if not preview:
                try:
                    state=deliver(folder,state,candidate,backend.post,backend.accepted)
                except Exception as error:
                    errors.append({'subject':name,'error':type(error).__name__})
        record['stage']='observe'
        rows=backend.observe(state)
        record['observed']=[{'subject':subject(r),'event_id':int(e['id']),
            'action':e['event'],'label':e['label']['name'],
            'trusted':actor(e) in trusted_accounts(r['project'])} for r in rows for e in relevant(r)]
        record['stage']='admission'
        result=plan(rows,state,backend.busy(),stops,limit)
        if had_pending:
            result['candidate']=None
            for decision in result['decisions']:
                if decision['reason'] == Reason.ELIGIBLE: decision['reason']=Reason.QUEUED
        record['decisions'].extend(result['decisions'])
        if not preview:
            atomic(state_path,result['state'])
            if result['candidate']:
                record['stage']='delivery'
                deliver(folder,result['state'],result['candidate'],backend.post,backend.accepted)
        if errors:
            record['errors']=errors
            return record
        record['ok']=not any(x['reason'] in ('active_event_missing', 'active_observation_missing')
                             for x in record['decisions'])
    except Exception as error:
        if str(error) == 'hub_lane_unmapped': record['reason']='hub_lane_unmapped'
        record['error']=type(error).__name__
        if getattr(backend,'operation',None):record['operation']=backend.operation
        # External diagnostics may contain credentials or private content.
    finally:history(local_files(folder)['history'],record)
    return record


def import_legacy(legacy, repo):
    active=legacy.get('active_issue')
    if active and not legacy.get('active_event_id'):
        raise ValueError('legacy active event must be identified before migration')
    return {'sent':[event_key(repo,e) for e in legacy.get('sent',[])],
            'active':{'subject':issue_subject(repo,active),'event_id':int(legacy['active_event_id'])} if active else None,
            'stopped':[issue_subject(repo,n) for n in legacy.get('stopped_issues',[])]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path)
    parser.add_argument('--local-files',action='store_true',help='print authoritative local file paths without querying services')
    parser.add_argument('--preview',action='store_true')
    parser.add_argument('--import-legacy',type=Path)
    parser.add_argument('--legacy-repo')
    args=parser.parse_args()
    if args.local_files:
        print(json.dumps({k:str(v) for k,v in local_files(data_path('label-dispatch')).items()}))
        return 0
    if args.config is None:parser.error('--config is required unless --local-files is used')
    os.umask(0o077)
    folder=data_path('label-dispatch');folder.mkdir(mode=0o700,exist_ok=True)
    with (local_files(folder)['lock']).open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            history(local_files(folder)['history'],{'ok':True,'decisions':[{'reason':Reason.LOCKED}]})
            return 0
        try:
            config=json.loads(args.config.read_text());validate(config)
        except Exception as error:
            history(local_files(folder)['history'],{'ok':False,'error':type(error).__name__})
            print('label-dispatch: invalid local settings',file=sys.stderr);return 1
        if args.import_legacy:
            try:
                repo=args.legacy_repo
                if repo not in {p['repo'] for p in config['projects']}:raise ValueError('unknown legacy repo')
                target=local_files(folder)['state']
                if target.exists():raise ValueError('state already exists')
                value=import_legacy(json.loads(args.import_legacy.read_text()),repo)
                if not args.preview:atomic(target,value)
                history(local_files(folder)['history'],{'ok':True,'preview':args.preview,'decisions':[{'reason':Reason.IMPORTED}]})
                print('label-dispatch: legacy state validated' if args.preview else 'label-dispatch: legacy state imported')
                return 0
            except Exception as error:
                history(local_files(folder)['history'],{'ok':False,'error':type(error).__name__})
                print('label-dispatch: legacy import refused',file=sys.stderr);return 1
        record=poll(config,folder,args.preview)
        print(json.dumps(record,ensure_ascii=False))
        return 0 if record['ok'] else 1

if __name__=='__main__':sys.exit(main())
