#!/usr/bin/env bash
# End-to-end check against a running stack. Exercises the whole patient journey
# (register -> profile -> upload -> triage chat -> doctor decision -> token) plus the doctor and
# admin dashboards and the AI seam, then asserts the access-control boundaries.
#
#   docker compose up -d db && (cd backend && npm run dev)
#   bash scripts/smoke.sh
#
# Needs the demo dataset: it logs in as the seeded dr.mehta and admin accounts.
# That is off by default now (SEED_DEMO_DATA=false), so a production-shaped boot
# has no such accounts and this script will not run against one -- by design.
#
# Needs curl and python3 on PATH. Writes scratch files next to itself.
set -u
cd "$(dirname "$0")"
API="${API:-http://localhost:4000}"
# Falls back to ../.env so this matches whatever the running backend loaded.
# No default: the secret is per-deployment now, and asserting against a guessed
# one would just fail confusingly.
SECRET="${AI_CALLBACK_SECRET:-$(sed -n 's/^AI_CALLBACK_SECRET=//p' ../.env 2>/dev/null | tr -d '
')}"
J='content-type: application/json'
fail=0
chk() { if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3 (want $1 got $2)"; fail=1; fi; }
code() { curl -s -o ./body -w '%{http_code}' "$@"; }

echo "== register patient =="
EMAIL="smoke$(date +%s)@demo.test"
c=$(code -X POST "$API/auth/register" -H "$J" -d "{\"email\":\"$EMAIL\",\"password\":\"password123\",\"full_name\":\"Smoke Patient\"}")
chk 201 "$c" "register"
TOK=$(python -c "import json;print(json.load(open('./body'))['token'])")
A="authorization: Bearer $TOK"

echo "== duplicate register rejected =="
c=$(code -X POST "$API/auth/register" -H "$J" -d "{\"email\":\"$EMAIL\",\"password\":\"password123\",\"full_name\":\"Dup\"}")
chk 400 "$c" "duplicate email"

echo "== short password rejected =="
c=$(code -X POST "$API/auth/register" -H "$J" -d '{"email":"x@y.test","password":"short","full_name":"X"}')
chk 400 "$c" "short password"

echo "== bad login =="
c=$(code -X POST "$API/auth/login" -H "$J" -d "{\"email\":\"$EMAIL\",\"password\":\"wrongpass1\"}")
chk 401 "$c" "wrong password"

echo "== no token =="
c=$(code "$API/me/profile"); chk 401 "$c" "unauthenticated profile"

echo "== auth/me =="
c=$(code "$API/auth/me" -H "$A"); chk 200 "$c" "auth/me"
python -c "
import json;d=json.load(open('./body'))
assert d['user']['role']=='patient', d
assert 'patient' in d
print('  ok  role=patient, patient block present')"

echo "== profile update =="
c=$(code -X PUT "$API/me/profile" -H "$J" -H "$A" -d '{"dob":"1996-06-15","gender":"female","blood_type":"B+","phone":"+91-9000012345","address":"12 Test Lane","lat":20.30,"lng":85.82,"insurance_provider":"Acme","policy_number":"AC-1","language":"hi","profile_complete":true}')
chk 200 "$c" "PUT profile"
python -c "
import json;d=json.load(open('./body'))
assert d['age'] in (28,29,30), d['age']
assert d['language']=='hi'
print('  ok  derived age =', d['age'])"

echo "== bad gender rejected =="
c=$(code -X PUT "$API/me/profile" -H "$J" -H "$A" -d '{"gender":"martian"}'); chk 400 "$c" "invalid enum"

echo "== conditions + relatives =="
c=$(code -X POST "$API/me/conditions" -H "$J" -H "$A" -d '{"kind":"allergy","label":"Sulfa drugs"}'); chk 201 "$c" "add condition"
c=$(code -X POST "$API/me/conditions" -H "$J" -H "$A" -d '{"kind":"nope","label":"x"}'); chk 400 "$c" "bad condition kind"
c=$(code -X POST "$API/me/relatives" -H "$J" -H "$A" -d '{"name":"Guardian One","contact":"+91-9000099999","relation":"guardian"}'); chk 201 "$c" "add relative"

echo "== aadhaar is recorded, never claimed verified =="
c=$(code -X POST "$API/me/aadhaar/verify" -H "$J" -H "$A" -d '{"aadhaar_number":"1234 5678 9012"}'); chk 200 "$c" "aadhaar recorded"
python -c "
import json;d=json.load(open('./body'))
assert d['aadhaar_last4']=='9012'
assert d['aadhaar_verified'] is False, 'must not claim a verification that never happened'
print('  ok  last4 stored, not marked verified')"
c=$(code -X POST "$API/me/aadhaar/verify" -H "$J" -H "$A" -d '{"aadhaar_number":"123"}'); chk 400 "$c" "short aadhaar"

echo "== document upload (image into postgres) =="
python -c "
import base64,pathlib
png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==')
pathlib.Path('./x.png').write_bytes(png)"
c=$(code -X POST "$API/me/documents" -H "$A" -F "file=@./x.png;type=image/png" -F "label=blood test" -F "description=smoke upload")
chk 201 "$c" "upload document"
FILE_ID=$(python -c "import json;print(json.load(open('./body'))['file_id'])")
c=$(code "$API/files/$FILE_ID" -H "$A"); chk 200 "$c" "download own file"
echo "  info file bytes: $(wc -c < ./body)"
c=$(code -X POST "$API/me/documents" -H "$A" -F "file=@./x.png;type=application/x-msdownload" -F "label=evil")
chk 400 "$c" "mime allowlist"

echo "== hospitals =="
c=$(code "$API/hospitals?lat=20.30&lng=85.82" -H "$A"); chk 200 "$c" "hospital list"
HOSP=$(python -c "import json;d=json.load(open('./body'));print(d[0]['id'], d[0]['name'], d[0]['distance_km'])")
echo "  info nearest: $HOSP"
HOSP_ID=$(echo "$HOSP" | cut -d' ' -f1)

echo "== preferred hospitals =="
c=$(code -X PUT "$API/me/preferred-hospitals" -H "$J" -H "$A" -d "{\"hospital_ids\":[\"$HOSP_ID\"]}"); chk 200 "$c" "set preferred"

echo "== ai conversation =="
c=$(code -X POST "$API/conversations" -H "$J" -H "$A" -d '{"kind":"ai"}'); chk 201 "$c" "create ai thread"
CONV=$(python -c "import json;print(json.load(open('./body'))['id'])")

echo "== the thread opens with a registration intake, asked one at a time =="
python -c "
import json,urllib.request

TOK='$TOK'
BASE='$API/conversations/$CONV'

def get():
    r=urllib.request.Request(BASE+'/messages',headers={'authorization':'Bearer '+TOK})
    return json.load(urllib.request.urlopen(r))

def post(path,body):
    r=urllib.request.Request(BASE+path,method='POST',
        headers={'authorization':'Bearer '+TOK,'content-type':'application/json'},
        data=json.dumps(body).encode())
    return json.load(urllib.request.urlopen(r))

asked=[]
for _ in range(10):
    d=get()
    open_intake=[m for m in d['messages']
                 if m['kind']=='mcq' and m['payload'].get('intake') and m['id'] not in asked]
    if not open_intake: break
    m=open_intake[0]
    qs=m['payload']['questions']
    assert len(qs)==1, 'intake must be asked one question at a time, got %d' % len(qs)
    assert m['body']==qs[0]['question'], 'the card header should be the question itself'
    asked.append(m['id'])
    out=post('/mcq-answer',{'message_id':m['id'],'answers':{qs[0]['id']:qs[0]['options'][0]}})
    assert out['triage_pending'] is False, 'intake alone must not fire a triage round'
else:
    raise SystemExit('  FAIL intake never finished')

assert len(asked)>=4, 'expected the full intake, got %d question(s)' % len(asked)
print('  ok  intake asked %d questions, one at a time, none triggering triage' % len(asked))

# Answering is recorded, but never echoed back as a second question message.
d=get()
kinds=[m['kind'] for m in d['messages']]
assert kinds.count('mcq_answer')==len(asked), kinds
assert d['messages'][-1]['kind']=='text', 'intake should end by handing over to the patient'
print('  ok  handed over: %s' % d['messages'][-1]['body'][:60])
" || fail=1

c=$(code -X POST "$API/conversations/$CONV/messages" -H "$J" -H "$A" -d '{"body":"my stomach hurts since morning and I feel dizzy","language":"hi"}')
chk 201 "$c" "send first message"
python -c "
import json,time,urllib.request
# A real triage turn is seconds, not milliseconds -- poll patiently or this is
# flaky against the ai profile while passing against the stub.
for _ in range(90):
    time.sleep(2)
    r=urllib.request.Request('$API/conversations/$CONV/messages',headers={'authorization':'Bearer $TOK'})
    d=json.load(urllib.request.urlopen(r))
    asked=[m for m in d['messages'] if m['kind']=='mcq' and not m['payload'].get('intake')]
    if asked and not d['triage_pending']: break
else:
    raise SystemExit('  FAIL no assistant mcq appeared: %s' % [m['kind'] for m in d['messages']])
mcq=asked[0]
qs=mcq['payload']['questions']
print('  ok  assistant mcq arrived with', len(qs), 'questions')
answers={q['id']: (q['options'][1] if len(q['options'])>1 else q['options'][0]) for q in qs[:2]}
open('./mcq.json','w').write(json.dumps({'message_id':mcq['id'],'answers':answers}))
" || fail=1

echo "== the assistant interviews before concluding, then routes without ticketing =="
python -c "
import json,time,urllib.request

TOK='$TOK'
BASE='$API/conversations/$CONV'

def get():
    r=urllib.request.Request(BASE+'/messages',headers={'authorization':'Bearer '+TOK})
    return json.load(urllib.request.urlopen(r))

def post(path,body):
    r=urllib.request.Request(BASE+path,method='POST',
        headers={'authorization':'Bearer '+TOK,'content-type':'application/json'},
        data=json.dumps(body).encode())
    return json.load(urllib.request.urlopen(r))

def settle(since=0):
    # triage is fired after the response is sent, so triage_pending is briefly
    # still false right after posting. Wait for the transcript to actually grow.
    for _ in range(90):
        time.sleep(2)
        d=get()
        if len(d['messages'])>since and not d['triage_pending']: return d
    return d

# A single alarming sentence used to be enough to end the interview. Now the
# assistant has a floor to clear, so drive it round by round.
answered=set()
rounds=0
d=settle()
for _ in range(9):
    kinds=[m['kind'] for m in d['messages']]
    if 'report' in kinds and 'status' in kinds: break
    asked=[m for m in d['messages']
           if m['kind']=='mcq' and not m['payload'].get('intake') and m['id'] not in answered]
    if not asked:
        raise SystemExit('  FAIL assistant stopped without asking or concluding: %s' % kinds)
    m=asked[-1]; answered.add(m['id']); rounds+=1
    qs=m['payload']['questions']
    n=len(d['messages'])
    post('/mcq-answer',{'message_id':m['id'],
                        'answers':{q['id']:q['options'][0] for q in qs}})
    d=settle(since=n)
else:
    raise SystemExit('  FAIL assistant never produced a report')

kinds=[m['kind'] for m in d['messages']]
if 'report' not in kinds or 'status' not in kinds:
    raise SystemExit('  FAIL expected report+status, got %s' % kinds)
assert rounds >= 2, 'assistant concluded after only %d follow-up round(s)' % rounds
print('  ok  interviewed over %d follow-up round(s) before concluding' % rounds)

rep=[m for m in d['messages'] if m['kind']=='report'][0]['payload']
st=[m for m in d['messages'] if m['kind']=='status'][-1]['payload']
hs=[m for m in d['messages'] if m['kind']=='hospital_suggestion']
print('  ok  report specialty=%s urgency=%s red_flag=%s' % (rep['specialty'],rep['urgency'],rep['red_flag']))
assert st['token_no'] is None, 'triage must not issue a token: %r' % st['token_no']
assert st['state']=='pending_review', st['state']
print('  ok  routed to dept=%s doctor=%s, no token yet (state=%s)' % (st['department'],st['doctor'],st['state']))
print('  ok  hospital suggestions:', len(hs[0]['payload']['hospitals']) if hs else 0)
open('./visit.txt','w').write(st['visit_id'])
" || fail=1

echo "== incremental polling loses nothing and repeats nothing =="
python -c "
import json,urllib.parse,urllib.request
def get(u):
    return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={'authorization':'Bearer $TOK'})))
base='$API/conversations/$CONV/messages'
full=[m['id'] for m in get(base)['messages']]
# Page two at a time so the walk is forced to cut through the group of messages
# one triage transaction writes, which all share a created_at to the microsecond.
seen=[];cur=cid=None
for _ in range(200):
    u=base+'?limit=2'+(('&after='+urllib.parse.quote(cur)+'&after_id='+cid) if cur else '')
    page=get(u)['messages']
    if not page: break
    seen+=[m['id'] for m in page]; cur=page[-1]['created_at']; cid=page[-1]['id']
else:
    raise SystemExit('  FAIL cursor never advanced past a tie group')
lost=[i for i in full if i not in seen]
dup=len(seen)-len(set(seen))
assert not lost, '  FAIL incremental polling dropped %d message(s)' % len(lost)
assert not dup, '  FAIL incremental polling re-sent %d message(s)' % dup
assert full==seen, '  FAIL paged order differs from unpaged order'
print('  ok  paged walk == full fetch (%d messages, limit=2)' % len(full))
" || fail=1

echo "== bad cursor is a 400, not a 500 =="
for q in 'after=5' 'after=2026' 'after_id=nope'; do
  c=$(code "$API/conversations/$CONV/messages?$q" -H "$A"); chk 400 "$c" "rejects ?$q"
done
c=$(code "$API/conversations/$CONV/messages?limit=-5" -H "$A"); chk 200 "$c" "clamps negative limit"

echo "== patient sees own visit =="
c=$(code "$API/me/visits" -H "$A"); chk 200 "$c" "GET /me/visits"
python -c "import json;d=json.load(open('./body'));assert len(d)>=1;assert d[0]['token_no'] is None;print('  ok  visits:',len(d),'awaiting a doctor, token',d[0]['token_no'])"
c=$(code "$API/me/bills" -H "$A"); chk 200 "$c" "GET /me/bills"
python -c "import json;d=json.load(open('./body'));assert d['billing_enabled'] is False;print('  ok  bills stub, visits in ledger:',len(d['visits']))"

echo "== patient cannot reach staff routes =="
c=$(code "$API/doctor/queue" -H "$A"); chk 403 "$c" "patient blocked from doctor queue"
c=$(code "$API/admin/overview" -H "$A"); chk 403 "$c" "patient blocked from admin"

echo "== doctor flow =="
c=$(code -X POST "$API/auth/login" -H "$J" -d '{"email":"dr.mehta@citygeneral.test","password":"password123"}'); chk 200 "$c" "doctor login"
DTOK=$(python -c "import json;print(json.load(open('./body'))['token'])"); DA="authorization: Bearer $DTOK"
c=$(code "$API/doctor/queue?scope=hospital" -H "$DA"); chk 200 "$c" "doctor queue"
python -c "
import json;d=json.load(open('./body'))
print('  ok  queue rows:',len(d))
assert len(d)>=1
v=[x for x in d if x['patient_name']=='Smoke Patient']
assert v, 'smoke patient not in queue'
assert v[0]['status']=='pending_review', v[0]['status']
print('  ok  smoke patient awaiting decision: urgency',v[0]['urgency'],'specialty',v[0]['specialty'])
open('./visit.txt','w').write(v[0]['id'])"
VISIT=$(cat ./visit.txt)
c=$(code "$API/doctor/visits/$VISIT" -H "$DA"); chk 200 "$c" "visit detail"
python -c "
import json;d=json.load(open('./body'))
assert d['triage'] is not None
assert len(d['documents'])>=1
assert len(d['relatives'])>=1
assert d['ai_conversation_id']
print('  ok  detail has triage, %d docs, %d relatives, ai thread' % (len(d['documents']),len(d['relatives'])))"
echo "== the doctor's decision is what issues the token =="
c=$(code -X POST "$API/doctor/visits/$VISIT/decision" -H "$J" -H "$DA" -d '{"decision":"admit","note":"come in today"}')
chk 200 "$c" "admit issues a token"
python -c "
import json;d=json.load(open('./body'))
assert d['token_no'] is not None, 'admit must issue a token'
assert d['status']=='waiting' and d['admitted_at']
print('  ok  token #%s issued on admit' % d['token_no'])"
c=$(code -X POST "$API/doctor/visits/$VISIT/decision" -H "$J" -H "$DA" -d '{"decision":"chat"}')
chk 400 "$c" "cannot decide a ticketed visit twice"
c=$(code -X POST "$API/doctor/visits/$VISIT/decision" -H "$J" -H "$DA" -d '{"decision":"maybe"}')
chk 400 "$c" "rejects an unknown decision"

c=$(code -X PATCH "$API/doctor/visits/$VISIT" -H "$J" -H "$DA" -d '{"urgency":1,"status":"in_consult","doctor_notes":"seen, escalating","claim":true}')
chk 200 "$c" "urgency override"
python -c "import json;d=json.load(open('./body'));assert d['urgency']==1 and d['urgency_overridden'] and d['status']=='in_consult';print('  ok  override recorded, flag set')"
c=$(code -X PATCH "$API/doctor/visits/$VISIT" -H "$J" -H "$DA" -d '{"urgency":99}'); chk 400 "$c" "urgency out of range"

echo "== doctor reads patient triage thread, cannot post =="
c=$(code "$API/conversations/$CONV/messages" -H "$DA"); chk 200 "$c" "doctor reads ai thread"
c=$(code -X POST "$API/conversations/$CONV/messages" -H "$J" -H "$DA" -d '{"body":"hi"}'); chk 403 "$c" "doctor cannot post in ai thread"

echo "== care team chat =="
PID=$(python -c "
import json,urllib.request
r=urllib.request.Request('$API/auth/me',headers={'authorization':'Bearer $TOK'})
print(json.load(urllib.request.urlopen(r))['user']['id'])")
c=$(code -X POST "$API/doctor/patients/$PID/conversation" -H "$J" -H "$DA"); chk 201 "$c" "open care team thread"
CT=$(python -c "import json;print(json.load(open('./body'))['id'])")
c=$(code -X POST "$API/conversations/$CT/messages" -H "$J" -H "$DA" -d '{"body":"Please come to room 4."}'); chk 201 "$c" "doctor posts"
c=$(code -X POST "$API/conversations/$CT/messages" -H "$J" -H "$A" -d '{"body":"on my way"}'); chk 201 "$c" "patient replies"
c=$(code "$API/conversations/$CT/messages" -H "$A"); chk 200 "$c" "care team transcript"
python -c "
import json;d=json.load(open('./body'))
roles=[m['sender_role'] for m in d['messages']]
assert 'doctor' in roles and 'patient' in roles, roles
assert d['triage_pending'] is False, 'care_team must never trigger triage'
print('  ok  roles in thread:',roles)"

echo "== admin flow =="
c=$(code -X POST "$API/auth/login" -H "$J" -d '{"email":"admin@citygeneral.test","password":"password123"}'); chk 200 "$c" "admin login"
ATOK=$(python -c "import json;print(json.load(open('./body'))['token'])"); AD="authorization: Bearer $ATOK"
c=$(code "$API/admin/overview" -H "$AD"); chk 200 "$c" "admin overview"
python -c "
import json;d=json.load(open('./body'))
print('  ok  today=%s in_queue=%s critical=%s depts=%d' % (d['totals']['today'],d['totals']['in_queue'],d['totals']['critical_today'],len(d['by_department'])))"
c=$(code "$API/admin/visits" -H "$AD"); chk 200 "$c" "admin visits"
c=$(code "$API/admin/departments" -H "$AD"); chk 200 "$c" "admin departments"
SPEC="ENT / Slug$(date +%s)"
c=$(code -X POST "$API/admin/departments" -H "$J" -H "$AD" -d "{\"name\":\"ENT\",\"specialty\":\"$SPEC\"}"); chk 201 "$c" "create department"
python -c "import json,re;d=json.load(open('./body'));assert re.fullmatch(r'ent_slug[0-9]+',d['specialty']),d;print('  ok  specialty slugified:',d['specialty'])"
# Read the id here, off the 201 -- the duplicate check below leaves a 400 error
# body behind, which has no id in it.
DEPT=$(python -c "import json;print(json.load(open('./body'))['id'])")
c=$(code -X POST "$API/admin/departments" -H "$J" -H "$AD" -d "{\"name\":\"ENT dup\",\"specialty\":\"$SPEC\"}"); chk 400 "$c" "duplicate specialty rejected"
c=$(code -X POST "$API/admin/doctors" -H "$J" -H "$AD" -d "{\"email\":\"dr.new$(date +%s)@citygeneral.test\",\"full_name\":\"Dr. New Hire\",\"password\":\"password123\",\"department_id\":\"$DEPT\"}")
chk 201 "$c" "create doctor"
NEWDOC=$(python -c "import json;print(json.load(open('./body'))['id'])")
c=$(code -X PATCH "$API/admin/doctors/$NEWDOC" -H "$J" -H "$AD" -d '{"is_available":false}'); chk 200 "$c" "toggle availability"
c=$(code "$API/admin/audit" -H "$AD"); chk 200 "$c" "audit trail"
python -c "
import json;d=json.load(open('./body'))
acts={x['action'] for x in d}
for want in ('triage.result_applied','visit.updated','admin.doctor_created'):
    assert want in acts, (want, sorted(acts))
# The trail is scoped to the caller's hospital. This run registered a patient and
# saved their profile; those belong to no hospital and must not appear here, or
# the scope filter is off and one hospital's admin is reading the whole platform.
leaked = acts & {'auth.register','auth.login','patient.profile_updated','patient.aadhaar_recorded'}
assert not leaked, '  FAIL unscoped rows in the hospital audit trail: %s' % sorted(leaked)
print('  ok  audit has', len(d), 'entries, all hospital-scoped')"

echo "== admin scoped to own hospital =="
c=$(code "$API/doctor/queue" -H "$AD"); chk 403 "$c" "admin blocked from doctor queue"

echo "== ai seam =="
c=$(code "$API/ai/health"); chk 200 "$c" "ai health"
python -c "import json;d=json.load(open('./body'));assert d['triage_backend'] in ('stub','http');print('  ok  triage backend:',d['triage_backend'])"
c=$(code "$API/ai/pending"); chk 403 "$c" "ai routes need secret"
if [ -z "$SECRET" ]; then
  echo "  skip AI_CALLBACK_SECRET is empty - skipping the authenticated /ai/* checks"
  echo "       (set it in .env, restart the backend, and rerun to cover them)"
else
c=$(code "$API/ai/pending" -H "x-ai-secret: $SECRET"); chk 200 "$c" "ai pending with secret"
c=$(code "$API/ai/pending" -H "x-ai-secret: wrong"); chk 403 "$c" "wrong secret"

echo "== async callback path =="
c=$(code -X POST "$API/conversations" -H "$J" -H "$A" -d '{"kind":"ai","force_new":true}'); chk 201 "$c" "second ai thread"
CONV2=$(python -c "import json;print(json.load(open('./body'))['id'])")
c=$(code -X POST "$API/conversations/$CONV2/messages" -H "$J" -H "$A" -d '{"body":"chest pain and cannot breathe"}'); chk 201 "$c" "msg on thread 2"
python -c "
import json,time,urllib.request
time.sleep(1)
r=urllib.request.Request('$API/ai/pending',headers={'x-ai-secret':'$SECRET'})
d=json.load(urllib.request.urlopen(r))
print('  ok  pending queue visible to service:',len(d))"
c=$(code -X POST "$API/ai/triage-callback" -H "$J" -H "x-ai-secret: $SECRET" -d '{"request_id":"11111111-1111-1111-1111-111111111111"}')
chk 404 "$c" "callback for unknown request"
fi

echo "== one assistant thread per problem =="
python -c "
import json,urllib.request

TOK='$TOK'
API='$API'

def call(method, path, body=None):
    r=urllib.request.Request(API+path,method=method,
        headers={'authorization':'Bearer '+TOK,'content-type':'application/json'},
        data=None if body is None else json.dumps(body).encode())
    return json.load(urllib.request.urlopen(r))

# An untouched thread is handed back, so opening the app twice does not litter
# the list; once it has been used, the next open is a fresh consultation.
a=call('POST','/conversations',{'kind':'ai'})
b=call('POST','/conversations',{'kind':'ai'})
assert a['id']==b['id'], 'an unused thread should be reused'
call('POST','/conversations/%s/messages' % a['id'],{'body':'my left knee is swollen and stiff'})
c=call('POST','/conversations',{'kind':'ai'})
assert c['id']!=a['id'], 'a used thread must not be reused'
d=call('POST','/conversations',{'kind':'ai','force_new':True})
assert d['id']!=c['id'], 'force_new must always start a new thread'
print('  ok  reuse-while-unused, split-once-used, force_new')

threads=call('GET','/conversations?kind=ai')
assert all(t['kind']=='ai' for t in threads), 'kind filter leaked another kind'
named=[t for t in threads if t['id']==a['id']][0]
assert named['title']=='my left knee is swollen and stiff', named['title']
assert named['patient_messages']==1, named['patient_messages']
print('  ok  %d threads, titled from the first complaint' % len(threads))
" || fail=1
c=$(code "$API/conversations?kind=nope" -H "$A"); chk 400 "$c" "rejects an unknown kind"

echo "== staff provisioning: the admin decides which emails may hold a session =="
python -c "
import json,time,urllib.request,urllib.error

API='$API'

def call(method,path,tok=None,body=None):
    r=urllib.request.Request(API+path,method=method)
    r.add_header('content-type','application/json')
    if tok: r.add_header('authorization','Bearer '+tok)
    d=None if body is None else json.dumps(body).encode()
    try:
        with urllib.request.urlopen(r,d,timeout=60) as x:
            return json.load(x) if x.length != 0 else None
    except urllib.error.HTTPError as e:
        return {'__err':e.code}

# Self-signup can never mint staff, whatever the body claims.
stamp=int(time.time())
u=call('POST','/auth/register',body={'email':'selfstaff%d@t.io'%stamp,
    'password':'pw123456','full_name':'Not Staff','role':'doctor'})
assert u['user']['role']=='patient', u['user']['role']
print('  ok  self-signup cannot claim a staff role')

# A forged Google token is a 401, not a 500.
assert call('POST','/auth/google',body={'id_token':'forged'})['__err'] in (401,403)
print('  ok  an unverifiable Google token is rejected, not a server error')
" || fail=1

echo "== 404 =="
c=$(code "$API/nope"); chk 404 "$c" "unknown route"

echo
if [ "$fail" = "0" ]; then echo "ALL SMOKE CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
