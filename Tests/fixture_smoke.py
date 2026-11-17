import os
import http.cookiejar
import json
import time
import urllib.request
from urllib.error import HTTPError, URLError

base = f"http://127.0.0.1:{os.environ.get('MAGPIE_FIXTURE_PORT', '8773')}"
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
for attempt in range(30):
    try:
        client.open(base + "/api/state", timeout=2)
    except HTTPError as error:
        assert error.code == 401
        break
    except URLError:
        time.sleep(.2)
else:
    raise AssertionError("Fixture server did not start")

state = json.load(client.open(base + "/api/state?k=fixture-only-not-a-real-key"))
assert state["served"] == 1
providers = json.load(client.open(base + "/api/providers"))
assert len(providers["providers"][0]["keyList"]) == 2
assert len(json.load(client.open(base + "/api/usage"))["series"]) == 8
assert len(json.load(client.open(base + "/api/settings"))["proxies"]) == 1
assert json.load(client.open(base + "/api/autobackup"))["on"] is True
assert json.load(client.open(base + "/api/davsync"))["kind"] == "webdav"
assert len(json.load(client.open(base + "/api/tune"))["agents"]) == 1
assert json.load(client.open(base + "/api/model-price"))["price"]["cache_read"] == 0.25
assert b"Cookie" in client.open(base + "/?mode=window&view=sessions").read()
print("PASS: unauthenticated 401, Cookie exchange, provider pool, usage series, proxies, autobackup, davsync, tune, model-price, web console session")
