#!/usr/bin/env python3
"""Exercise the real Network.framework HTTP service in an isolated temporary library."""
import json,os,pathlib,subprocess,sys,tempfile,time,urllib.request,urllib.error,uuid,socket
binary=str(pathlib.Path(sys.argv[1]).resolve()); token='synthetic-ci-token-not-a-user-secret'
with tempfile.TemporaryDirectory() as directory:
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 env=dict(os.environ,CAN_CONNECT_TEST_TOKEN=token)
 p=subprocess.Popen([binary,'--headless','--library',directory,'--port',str(port)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 def call(path,data=None,auth=True):
  headers={'Content-Type':'application/json'}
  if auth:headers['Authorization']='Bearer '+token
  req=urllib.request.Request('http://127.0.0.1:'+str(port)+path,data=None if data is None else json.dumps(data).encode(),headers=headers)
  try:
   with urllib.request.urlopen(req,timeout=5) as response:return response.status,json.load(response)
  except urllib.error.HTTPError as error:return error.code,json.load(error)
 try:
  for _ in range(80):
   if p.poll() is not None:raise RuntimeError(p.stderr.read().decode())
   try:
    if call('/v1/health')[0]==200:break
   except OSError:pass
   time.sleep(.25)
  else:raise RuntimeError('Service did not become ready')
  assert call('/v1/vehicles',auth=False)[0]==401
  vehicle={'id':str(uuid.uuid4()),'name':'Synthetic API vehicle','year':'2026','make':'Test','model':'Fixture','vin':'','notes':''}
  assert call('/v1/vehicles',vehicle)[0]==201
  recording={'schemaVersion':1,'vehicleID':vehicle['id'],'name':'Synthetic upload','source':'API integration fixture','samples':[{'timestamp':'2026-10-23T12:00:00.125Z','latitude':49.1,'longitude':-123.9,'signals':{'speedKph':60}},{'timestamp':'2026-10-23T12:00:01.125Z','latitude':49.1001,'longitude':-123.9,'signals':{'speedKph':61}}]}
  status,receipt=call('/v1/recordings',recording);assert status==202
  for _ in range(80):
   status,processed=call('/v1/receipts/'+receipt['id'])
   if processed['status']=='processed':break
   if processed['status']=='failed':raise AssertionError(processed)
   time.sleep(.1)
  else:raise AssertionError('Receipt did not finish')
  status,duplicate=call('/v1/recordings',recording);assert status==200 and duplicate['id']==receipt['id']
  status,trips=call('/v1/trips');assert len(trips['trips'])==1
  _,trip=call('/v1/trips/'+trips['trips'][0]['id']);assert trip['samples'][0]['signals']['speedKph']==60
  assert call('/v1/recordings',dict(recording,vehicleID=str(uuid.uuid4())))[0]==422
  manifest=json.loads((pathlib.Path(directory)/'library.json').read_text());assert len(manifest['receipts'])==1
  assert len(list((pathlib.Path(directory)/'Originals').iterdir()))==1
  print('API integration passed: auth, vehicle setup, upload, processing receipt, byte deduplication, trip retrieval, vehicle validation, durable original.')
 finally:
  p.terminate()
  try:p.wait(timeout=5)
  except subprocess.TimeoutExpired:p.kill();p.wait()
