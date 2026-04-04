import base64
import json
import os
import time
from pathlib import Path
from urllib import error, request
from zipfile import ZIP_DEFLATED, ZipFile

root = Path('/tmp/function-package')
root.mkdir(parents=True, exist_ok=True)

files = {
    'function_app.py': os.environ['FUNCTION_APP_PY'],
    'host.json': os.environ['HOST_JSON'],
    'requirements.txt': os.environ['REQUIREMENTS_TXT'],
}

for name, content in files.items():
    (root / name).write_text(content, encoding='utf-8')

zip_path = Path('/tmp/function-package.zip')
with ZipFile(zip_path, 'w', ZIP_DEFLATED) as archive:
    for name in files:
        archive.write(root / name, arcname=name)

auth = base64.b64encode(f"{os.environ['PUBLISH_USER']}:{os.environ['PUBLISH_PASSWORD']}".encode('utf-8')).decode('ascii')
headers = {
    'Authorization': f'Basic {auth}',
    'Content-Type': 'application/zip',
}
deploy_url = f"https://{os.environ['SCM_HOST']}/api/zipdeploy?isAsync=true"


def read_error(exc: error.HTTPError) -> str:
    try:
        return exc.read().decode('utf-8', errors='replace')
    except Exception:
        return str(exc)


try:
    deploy_request = request.Request(
        deploy_url,
        data=zip_path.read_bytes(),
        headers=headers,
        method='POST',
    )
    with request.urlopen(deploy_request) as response:
        status_url = response.headers.get('Location') or response.headers.get('location')
        response.read()
except error.HTTPError as exc:
    raise RuntimeError(read_error(exc)) from exc

if not status_url:
    raise RuntimeError('zipdeploy did not return a deployment status URL.')

for _ in range(60):
    try:
        status_request = request.Request(status_url, headers={'Authorization': f'Basic {auth}'})
        with request.urlopen(status_request) as response:
            status_payload = json.loads(response.read().decode('utf-8'))
    except error.HTTPError as exc:
        raise RuntimeError(read_error(exc)) from exc

    deployment_status = status_payload.get('status')
    if deployment_status == 4:
        Path(os.environ['AZ_SCRIPTS_OUTPUT_PATH']).write_text(
            json.dumps({'deploymentStatus': 'succeeded'}),
            encoding='utf-8',
        )
        break

    if deployment_status == 3:
        raise RuntimeError(json.dumps(status_payload, ensure_ascii=False))

    time.sleep(5)
else:
    raise TimeoutError('Timed out waiting for zip deployment to finish.')