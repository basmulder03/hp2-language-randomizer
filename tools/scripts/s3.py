"""Minimal S3 client (standard library only): AWS Signature V4, multipart
upload, streaming download. Enough to keep the private assets zip on any
S3-compatible store (AWS, Garage, MinIO, ...), path-style addressing.

Settings come from environment variables, then ~/.config/hp2mod/s3.ini
(section [s3]); nothing personal lives in the repository:

    endpoint = https://s3.example.com         HP2_S3_ENDPOINT
    bucket   = private                        HP2_S3_BUCKET
    region   = us-east-1                      HP2_S3_REGION (AWS_DEFAULT_REGION)
    key      = hp2/hp2-language-assets.zip    HP2_S3_KEY
    access_key = ...                          AWS_ACCESS_KEY_ID
    secret_key = ...                          AWS_SECRET_ACCESS_KEY
    access_key_command = <shell command printing the access key>
    secret_key_command = <shell command printing the secret key>

The *_command options let the keys stay in a secrets manager (e.g. sops).
"""
import configparser
import datetime
import hashlib
import hmac
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("HP2_S3_CONFIG") or Path.home() / ".config" / "hp2mod" / "s3.ini")
PART_SIZE = 64 * 1024 * 1024   # below proxy limits such as Cloudflare's 100 MB
CHUNK = 1024 * 1024
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()


class S3Error(Exception):
    pass


class Settings:
    def __init__(self, endpoint, bucket, region, key, access_key, secret_key):
        self.endpoint = (endpoint or "").rstrip("/")
        self.bucket = bucket
        self.region = region
        self.key = key
        self.access_key = access_key
        self.secret_key = secret_key


def load_settings(**overrides) -> Settings:
    cfg = configparser.ConfigParser(interpolation=None)
    if CONFIG_PATH.exists():
        cfg.read(CONFIG_PATH)
    sec = cfg["s3"] if cfg.has_section("s3") else {}

    def get(name, env_names, default=None):
        if overrides.get(name):
            return overrides[name]
        for env in env_names:
            if os.environ.get(env):
                return os.environ[env]
        if name in sec and sec[name]:
            return sec[name]
        command = sec.get(f"{name}_command") if sec else None
        if command:
            out = subprocess.run(command, shell=True, capture_output=True, text=True)
            if out.returncode != 0 or not out.stdout.strip():
                raise S3Error(f"{name}_command failed: {out.stderr.strip()[:200]}")
            return out.stdout.strip()
        return default

    s = Settings(
        endpoint=get("endpoint", ["HP2_S3_ENDPOINT"]),
        bucket=get("bucket", ["HP2_S3_BUCKET"]),
        region=get("region", ["HP2_S3_REGION", "AWS_DEFAULT_REGION"], "us-east-1"),
        key=get("key", ["HP2_S3_KEY"], "hp2/hp2-language-assets.zip"),
        access_key=get("access_key", ["AWS_ACCESS_KEY_ID"]),
        secret_key=get("secret_key", ["AWS_SECRET_ACCESS_KEY"]),
    )
    missing = [n for n in ("endpoint", "bucket", "access_key", "secret_key") if not getattr(s, n)]
    if missing:
        raise S3Error(f"S3 settings missing: {', '.join(missing)} (see {CONFIG_PATH} or HP2_S3_* / AWS_* variables)")
    return s


# --- Signature V4 --------------------------------------------------------------

def _hmac(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def sign(method: str, url: str, headers: dict, payload_sha256: str, access_key: str, secret_key: str,
         region: str, now: datetime.datetime = None, service: str = "s3") -> dict:
    """Headers for a Signature V4 request (adds host, x-amz-date,
    x-amz-content-sha256, authorization)."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    parts = urllib.parse.urlsplit(url)
    host = parts.netloc
    canonical_uri = urllib.parse.quote(urllib.parse.unquote(parts.path) or "/", safe="/~")
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    canonical_query = "&".join(
        f"{urllib.parse.quote(k, safe='-_.~')}={urllib.parse.quote(v, safe='-_.~')}" for k, v in sorted(query))
    all_headers = {k.lower(): str(v).strip() for k, v in headers.items()}
    all_headers["host"] = host
    all_headers["x-amz-date"] = amz_date
    all_headers["x-amz-content-sha256"] = payload_sha256
    signed = sorted(all_headers)
    canonical_headers = "".join(f"{h}:{all_headers[h]}\n" for h in signed)
    signed_headers = ";".join(signed)
    canonical_request = "\n".join([method, canonical_uri, canonical_query, canonical_headers,
                                   signed_headers, payload_sha256])
    scope = f"{datestamp}/{region}/{service}/aws4_request"
    string_to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope,
                                hashlib.sha256(canonical_request.encode()).hexdigest()])
    k = _hmac(("AWS4" + secret_key).encode(), datestamp)
    k = _hmac(k, region)
    k = _hmac(k, service)
    k = _hmac(k, "aws4_request")
    signature = hmac.new(k, string_to_sign.encode(), hashlib.sha256).hexdigest()
    all_headers["authorization"] = (f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
                                    f"SignedHeaders={signed_headers}, Signature={signature}")
    return all_headers


class Client:
    def __init__(self, s: Settings):
        self.s = s

    def url(self, key: str, query: str = "") -> str:
        u = f"{self.s.endpoint}/{urllib.parse.quote(self.s.bucket)}/{urllib.parse.quote(key, safe='/')}"
        return u + (f"?{query}" if query else "")

    def request(self, method, key, query="", body=b"", headers=None, stream=False):
        url = self.url(key, query)
        payload_hash = hashlib.sha256(body).hexdigest() if body else EMPTY_SHA256
        h = sign(method, url, headers or {}, payload_hash, self.s.access_key, self.s.secret_key, self.s.region)
        h.pop("host")
        req = urllib.request.Request(url, data=body if body else None, method=method, headers=h)
        try:
            resp = urllib.request.urlopen(req, timeout=300)
        except urllib.error.HTTPError as e:
            detail = e.read()[:300].decode(errors="replace")
            raise S3Error(f"{method} {key}: HTTP {e.code} {detail}") from None
        except urllib.error.URLError as e:
            raise S3Error(f"{method} {key}: {e.reason}") from None
        if stream:
            return resp
        with resp:
            return resp.status, dict(resp.headers), resp.read()

    def head(self, key):
        try:
            _, headers, _ = self.request("HEAD", key)
        except S3Error as e:
            if "HTTP 404" in str(e):
                return None
            raise
        return {k.lower(): v for k, v in headers.items()}

    def upload_file(self, path: Path, key: str, metadata: dict = None, progress=print):
        size = path.stat().st_size
        meta = {f"x-amz-meta-{k}": v for k, v in (metadata or {}).items()}
        _, _, body = self.request("POST", key, "uploads=", headers=meta)
        upload_id = _xml_text(body, "UploadId")
        parts = []
        try:
            with path.open("rb") as f:
                n = 0
                while True:
                    chunk = f.read(PART_SIZE)
                    if not chunk:
                        break
                    n += 1
                    q = f"partNumber={n}&uploadId={urllib.parse.quote(upload_id, safe='')}"
                    _, headers, _ = self.request("PUT", key, q, body=chunk)
                    etag = {k.lower(): v for k, v in headers.items()}["etag"]
                    parts.append((n, etag))
                    progress(f"  part {n}: {min(n * PART_SIZE, size) / 2**30:.2f}/{size / 2**30:.2f} GiB")
            xml = "<CompleteMultipartUpload>" + "".join(
                f"<Part><PartNumber>{n}</PartNumber><ETag>{etag}</ETag></Part>" for n, etag in parts
            ) + "</CompleteMultipartUpload>"
            self.request("POST", key, f"uploadId={urllib.parse.quote(upload_id, safe='')}", body=xml.encode())
        except BaseException:
            try:
                self.request("DELETE", key, f"uploadId={urllib.parse.quote(upload_id, safe='')}")
            except S3Error:
                pass
            raise

    def download_file(self, key: str, path: Path, progress=print) -> str:
        """Stream key to path; returns the SHA-256 of what was written."""
        digest = hashlib.sha256()
        tmp = path.with_suffix(path.suffix + ".part")
        with self.request("GET", key, stream=True) as resp, tmp.open("wb") as out:
            total = int(resp.headers.get("Content-Length") or 0)
            done = next_report = 0
            while True:
                chunk = resp.read(CHUNK)
                if not chunk:
                    break
                out.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                if done >= next_report:
                    progress(f"  {done / 2**30:.2f}/{total / 2**30:.2f} GiB")
                    next_report += 512 * CHUNK
        tmp.replace(path)
        return digest.hexdigest()


def _xml_text(body: bytes, tag: str) -> str:
    root = ET.fromstring(body)
    for el in root.iter():
        if el.tag.split("}")[-1] == tag:
            return el.text
    raise S3Error(f"no <{tag}> in response")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8 * CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()
