#!/usr/bin/env bash
# End-to-end check against a running stack. Exercises the whole patient journey
# (register -> profile -> upload -> triage chat -> token) plus the doctor and
# admin dashboards and the AI seam, then asserts the access-control boundaries.
#
#   docker compose up -d db && (cd backend && npm run dev)
#   bash scripts/smoke.sh
#
# Needs curl and python3 on PATH. Writes scratch files next to itself.
set -u
cd "$(dirname "$0")"
API="${API:-http://localhost:4000}"
SECRET="${AI_CALLBACK_SECRET:-dev-callback-secret}"
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

echo "== aadhaar mock =="
c=$(code -X POST "$API/me/aadhaar/verify" -H "$J" -H "$A" -d '{"aadhaar_number":"1234 5678 9012"}'); chk 200 "$c" "aadhaar mock"
python -c "
import json;d=json.load(open('./body'));assert d['aadhaar_last4']=='9012' and d['mock'] is True;print('  ok  last4 stored, flagged mock')"
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

c=$(code -X POST "$API/conversations/$CONV/messages" -H "$J" -H "$A" -d '{"body":"my stomach hurts since morning and I feel dizzy","language":"hi"}')
chk 201 "$c" "send first message"
python -c "
import json,time,urllib.request
for _ in range(40):
    time.sleep(0.2)
    r=urllib.request.Request('$API/conversations/$CONV/messages',headers={'authorization':'Bearer $TOK'})
    d=json.load(urllib.request.urlopen(r))
    kinds=[m['kind'] for m in d['messages']]
    if 'mcq' in kinds: break
else:
    raise SystemExit('  FAIL no mcq message appeared: %s' % kinds)
mcq=[m for m in d['messages'] if m['kind']=='mcq'][0]
qs=mcq['payload']['questions']
print('  ok  mcq arrived with', len(qs), 'questions')
open('./mcq.json','w').write(json.dumps({'message_id':mcq['id'],'answers':{qs[0]['id']:qs[0]['options'][1],qs[1]['id']:qs[1]['options'][0]}}))
" || fail=1

echo "== answer mcq -> report + token =="
c=$(code -X POST "$API/conversations/$CONV/mcq-answer" -H "$J" -H "$A" -d @./mcq.json); chk 201 "$c" "submit mcq answers"
python -c "
import json,time,urllib.request
for _ in range(40):
    time.sleep(0.2)
    r=urllib.request.Request('$API/conversations/$CONV/messages',headers={'authorization':'Bearer $TOK'})
    d=json.load(urllib.request.urlopen(r))
    kinds=[m['kind'] for m in d['messages']]
    if 'report' in kinds and 'status' in kinds: break
else:
    raise SystemExit('  FAIL expected report+status, got %s' % kinds)
rep=[m for m in d['messages'] if m['kind']=='report'][0]['payload']
st=[m for m in d['messages'] if m['kind']=='status'][-1]['payload']
hs=[m for m in d['messages'] if m['kind']=='hospital_suggestion']
print('  ok  report specialty=%s urgency=%s red_flag=%s' % (rep['specialty'],rep['urgency'],rep['red_flag']))
print('  ok  token #%s dept=%s doctor=%s' % (st['token_no'],st['department'],st['doctor']))
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
python -c "import json;d=json.load(open('./body'));assert len(d)>=1;print('  ok  visits:',len(d),'token',d[0]['token_no'])"
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
print('  ok  smoke patient in queue: token',v[0]['token_no'],'urgency',v[0]['urgency'],'specialty',v[0]['specialty'])
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
c=$(code -X POST "$API/admin/departments" -H "$J" -H "$AD" -d "{\"name\":\"ENT dup\",\"specialty\":\"$SPEC\"}"); chk 400 "$c" "duplicate specialty rejected"
DEPT=$(python -c "import json;print(json.load(open('./body'))['id'])")
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
print('  ok  audit has', len(d), 'entries incl triage + override + provisioning')"

echo "== admin scoped to own hospital =="
c=$(code "$API/doctor/queue" -H "$AD"); chk 403 "$c" "admin blocked from doctor queue"

echo "== ai seam =="
c=$(code "$API/ai/health"); chk 200 "$c" "ai health"
python -c "import json;d=json.load(open('./body'));assert d['triage_backend']=='stub';print('  ok  triage backend:',d['triage_backend'])"
c=$(code "$API/ai/pending"); chk 403 "$c" "ai routes need secret"
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

echo "== 404 =="
c=$(code "$API/nope"); chk 404 "$c" "unknown route"

echo
if [ "$fail" = "0" ]; then echo "ALL SMOKE CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
