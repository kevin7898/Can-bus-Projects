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
  recording_id=str(uuid.uuid4());fill_id=str(uuid.uuid4())
  recording={'schemaVersion':2,'producer':{'app':'API integration fixture','version':'2','platform':'test'},
             'sources':[{'id':'gps','kind':'gps','name':'Synthetic GPS'},{'id':'obd','kind':'obd','name':'Synthetic OBD'}],
             'vehicles':[{'id':vehicle['id'],'name':vehicle['name'],'year':'2026','make':'Test','model':'Fixture'}],
             'recordings':[{'recordingID':recording_id,'vehicleID':vehicle['id'],'name':'Synthetic upload',
               'startedAt':'2026-10-23T12:00:00.125Z','endedAt':'2026-10-23T12:00:01.125Z','sourceIDs':['gps','obd'],
               'gpsPoints':[{'timestamp':'2026-10-23T12:00:00.125Z','latitude':49.1,'longitude':-123.9,'horizontalAccuracyM':5,'speedMps':10,'sourceID':'gps'},{'timestamp':'2026-10-23T12:00:01.125Z','latitude':49.1001,'longitude':-123.9,'horizontalAccuracyM':5,'speedMps':11,'sourceID':'gps'}],
               'signalSamples':[{'timestamp':'2026-10-23T12:00:00.125Z','values':{'speedKph':60,'rpm':832},'sourceID':'obd'},{'timestamp':'2026-10-23T12:00:01.125Z','values':{'speedKph':61,'rpm':840},'sourceID':'obd'}],
               'events':[],'coverage':[],'isSample':False}],
             'fuelEntries':[{'id':fill_id,'vehicleID':vehicle['id'],'date':'2026-10-24T12:00:00.000Z','litresPurchased':40,'totalCost':60,'currencyCode':'CAD','odometerKm':12000,'isFullFill':True,'isSample':False,
               'receipt':{'fileName':'synthetic-receipt.jpg','mediaType':'image/jpeg','byteCount':1234,'sha256':'a'*64}}]}
  upload_path='/v1/recordings?vehicleID='+vehicle['id']
  status,receipt=call(upload_path,recording);assert status==202
  for _ in range(80):
   status,processed=call('/v1/receipts/'+receipt['id'])
   if processed['status']=='processed':break
   if processed['status']=='failed':raise AssertionError(processed)
   time.sleep(.1)
  else:raise AssertionError('Receipt did not finish')
  status,duplicate=call(upload_path,recording);assert status==200 and duplicate['id']==receipt['id']
  changed=json.loads(json.dumps(recording));changed['recordings'][0]['name']='Conflicting bytes'
  assert call(upload_path,changed)[0]==409
  status,trips=call('/v1/trips');assert len(trips['trips'])==1
  _,archive=call('/v1/trips/'+trips['trips'][0]['id']);trip=archive['recordings'][0]
  assert archive['schemaVersion']==2 and trip['recordingID'].lower()==recording_id.lower()
  assert trip['signalSamples'][0]['values']['speedKph']==60
  assert [(s['latitude'],s['longitude']) for s in trip['gpsPoints']]==[(49.1,-123.9),(49.1001,-123.9)]
  assert [s['values']['rpm'] for s in trip['signalSamples']]==[832,840]
  assert archive['fuelEntries'][0]['receipt']['sha256']=='a'*64
  assert call('/v1/recordings?vehicleID='+str(uuid.uuid4()),recording)[0]==422
  manifest=json.loads((pathlib.Path(directory)/'library.json').read_text());assert manifest['schemaVersion']==3 and len(manifest['receipts'])==1
  assert manifest['fuelEntries'][0]['id'].lower()==fill_id.lower() and manifest['fuelEntries'][0]['receipt']['sha256']=='a'*64
  assert len(list((pathlib.Path(directory)/'Originals').iterdir()))==1
  original=next((pathlib.Path(directory)/'Originals').iterdir()); assert json.loads(original.read_text())==recording
  print('API integration passed: v2 archive in v3 annotation-sidecar library, mixed GPS/OBD and fill receipt, stable IDs, exact original, auth, processing receipt, hash deduplication/conflict, trip retrieval, vehicle validation.')
 finally:
  p.terminate()
  try:p.wait(timeout=5)
  except subprocess.TimeoutExpired:p.kill();p.wait()
