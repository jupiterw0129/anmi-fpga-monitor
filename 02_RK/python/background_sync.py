"""Device-authenticated, confirmed-only background exchange, executed on RK."""
import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.request import Request, urlopen
from urllib.error import HTTPError

HOME = Path('/userdata/board_cloud')


def jpeg_size(data):
    index = 2
    while index + 9 < len(data):
        if data[index] != 255:
            index += 1;continue
        marker = data[index+1];index += 2
        if marker in (216,217):continue
        length = int.from_bytes(data[index:index+2], 'big')
        if length < 2 or index+length > len(data):break
        if marker in (192,193,194,195,197,198,199,201,202,203,205,206,207) and length >= 7:
            return int.from_bytes(data[index+5:index+7], 'big'), int.from_bytes(data[index+3:index+5], 'big')
        index += length
    raise ValueError('背景 JPEG 尺寸无效')


def validate(bundle, device_id):
    meta = bundle['background']
    data = base64.b64decode(bundle['content_base64'], validate=True)
    if (meta['device_id'] != device_id or type(meta['background_version']) is not int
            or meta['background_version'] < 1 or meta['rotation_deg'] != 0
            or meta['mirrored'] is not False or meta['coordinate_transform_version'] != 'camera-frame-v1'
            or meta['crop'] != dict(x=0, y=0, width=1, height=1)
            or meta['content_type'] != 'image/jpeg'
            or not 320 <= meta['width'] <= 1920 or not 180 <= meta['height'] <= 1080
            or meta['width'] * 9 != meta['height'] * 16
            or not 0 < len(data) <= 5 * 1024 * 1024 or len(data) != meta['size_bytes']
            or hashlib.sha256(data).hexdigest() != meta['sha256']
            or not data.startswith(b'\xff\xd8') or not data.endswith(b'\xff\xd9')
            or jpeg_size(data) != (meta['width'], meta['height'])):
        raise ValueError('背景校验失败，保留原背景')
    return data


def atomic(path, data):
    fd, temp = tempfile.mkstemp(prefix='.background_', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            os.chmod(temp, 0o600)
            out.write(data);out.flush();os.fsync(out.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):os.unlink(temp)


class BackgroundSync:
    def __init__(self, home=HOME):
        self.home = Path(home)
        self.config = json.loads((self.home/'config.json').read_text())
        self.device_id = self.config['device_id']
        token = Path(self.config['device_token_file'])
        self.token = (token if token.is_absolute() else self.home/token).read_text().strip()
        self.url = self.config['server_url'].rstrip('/')+f'/api/v1/devices/{self.device_id}/background/device'

    def cached(self):
        path = self.home/'confirmed_background.json'
        if not path.exists():return dict(background=None, content_base64=None)
        result = json.loads(path.read_text())
        validate(result, self.device_id)
        return result

    def request(self, url, data=None):
        headers = {'X-Device-Token': self.token}
        if data is not None:
            headers.update({'Content-Type': 'image/jpeg', 'X-Content-SHA256': hashlib.sha256(data).hexdigest()})
        try:
            with urlopen(Request(url, data=data, headers=headers, method='PUT' if data is not None else 'GET'), timeout=6) as response:
                raw = response.read(8 * 1024 * 1024 + 1)
                if len(raw) > 8 * 1024 * 1024:raise ValueError('背景响应过大')
                return json.loads(raw)
        except HTTPError as error:
            if error.code == 409:raise ValueError('背景已被修改或手机正在设置，请刷新后重新确认') from None
            raise ValueError('云端背景请求失败 HTTP '+str(error.code)) from None

    def exchange(self, known_version=None, data=None, expected_version=None):
        """A failed upload is never silently queued for a future unrelated session."""
        import fcntl
        result = dict(sync_error=None, committed=False)
        if data is not None:
            try:
                if type(expected_version) is not int:raise ValueError('请等待背景同步后再拍摄')
                self.request(self.url+'?expected_version='+str(expected_version), data)
                result['committed'] = True
            except Exception as error:
                result['sync_error'] = str(error) if isinstance(error, ValueError) else '背景提交未确认，请检查网络并刷新'
        try:
            # Serialize refreshes; the metadata and bytes form one atomic file.
            with (self.home/'background_sync.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                cached = self.cached()
                version = cached['background']['background_version'] if cached['background'] else 0
                bundle = self.request(self.url+'?known_version='+str(version))
                meta = bundle['background']
                if meta and meta['background_version'] < version:
                    raise ValueError('云端背景版本回退，保留原背景')
                if meta and meta['background_version'] != version:
                    validate(bundle, self.device_id)
                    atomic(self.home/'confirmed_background.json', json.dumps(bundle).encode())
                    cached = bundle
                elif meta != cached['background']:
                    raise ValueError('背景版本信息不一致，保留原背景')
        except Exception as error:
            if not result['sync_error']:
                result['sync_error'] = str(error) if isinstance(error, ValueError) else '背景同步失败，保留原背景'
        cached = self.cached()
        meta = cached['background']
        result['background'] = meta
        result['content_base64'] = cached['content_base64'] if meta and meta['background_version'] != known_version else None
        return result
