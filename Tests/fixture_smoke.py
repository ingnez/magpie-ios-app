import http.cookiejar
import json
import time
import urllib.request
from urllib.error import HTTPError, URLError

base = "http://127.0.0.1:8773"
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
assert b"Cookie" in client.open(base + "/?mode=window&view=sessions").read()
print("PASS: unauthenticated 401, Cookie exchange, provider pool, usage series, web console session")
