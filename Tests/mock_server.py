"""Local-only API fixture for iOS UI tests. Never contacts an upstream service."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

SETTINGS = {"version": "test-fixture", "redact": True, "redactPersonal": True,
            "redactRules": [{"kind": "CORP", "regex": "INTERNAL_[A-Z]+"}], "redactAllow": [], "lan": False}
PROVIDER = {"id": "demo", "name": "OpenAI 演示", "ready": True, "chat": "https://api.example.invalid/v1", "preset": "custom", "routing": "rotate",
            "headers": {"X-Project": "test"}, "chosen": ["gpt-demo"], "contexts": {"gpt-demo": 128000},
            "keyList": [{"id": "k1", "name": "主 Key", "masked": "test-••••-0001", "active": True, "on": True},
                        {"id": "k2", "name": "备用 Key", "masked": "test-••••-0002", "active": False, "on": True, "weight": 2}],
            "models": [{"id": "gpt-demo", "name": "GPT 演示模型", "on": True, "context": 128000, "images": True, "efforts": ["low", "medium", "high"]}], "exposed": 1}
GROUP = {"id": "coding", "name": "编程组演示", "ref": "group/coding", "members": ["demo/gpt-demo"], "routing": "manual", "ready": True, "picked": "demo/gpt-demo", "rules": [{"use": "demo/gpt-demo", "tokens": 32000, "where": [{"field": "tokens", "op": "gte", "value": "32000"}]}]}
STATE = {"settings": SETTINGS, "served": 1, "agents": [{"id": "claude", "name": "Claude Code 演示", "wired": True, "path": "~/.claude/settings.json", "fields": [{"key": "model", "label": "主模型", "value": "group/coding", "options": [{"value": "group/coding", "label": "编程组演示", "ref": "group/coding", "fastFor": "claude"}]}]}], "profiles": [{"name": "开发方案", "summary": "Claude → 编程组", "inUse": True}]}
KEY = {"id": "caller-demo", "name": "移动端演示", "masked": "test-••••-9001", "limit": {"period": "week", "tokens": 1000000, "cost": 10}, "used": {"period": "week", "tokens": 12345, "cost": .25, "reset": "2026-11-23T00:00:00+08:00"}}
RECORD = {"key": "1001", "t": "2026-11-17T15:30:00+08:00", "what": "chat", "model": "gpt-demo", "n": 1, "values": [{"p": "{{EMAIL_demo}}", "k": "EMAIL", "b": "personal", "l": 17, "n": 1, "known": True}]}
USAGE = {"calls": 126, "errors": 2, "input": 125000, "output": 42000, "cost": .75, "bucket": "hour", "series": [{"label": f"{hour:02d}:00", "calls": calls, "input": calls * 900, "output": calls * 300, "cost": calls * .005} for hour, calls in zip(range(8, 16), [3, 8, 21, 15, 11, 26, 30, 12])]}
RESPONSES = {
    "/api/state": STATE, "/api/settings": SETTINGS,
    "/api/providers": {"providers": [PROVIDER]},
    "/api/groups": {"groups": [GROUP], "models": [{"id": "demo/gpt-demo", "name": "GPT 演示模型", "provider": "demo", "providerName": "OpenAI 演示"}]},
    "/api/usage": USAGE, "/api/usage/quotas": [],
    "/api/caller-keys": {"keys": [KEY]},
    "/api/masking/summary": {"requests": 1, "n": 1}, "/api/masking/records": {"records": [RECORD], "more": False},
    "/api/masking/sent": {"body": "联系 {{EMAIL_demo}}"},
    "/api/agent-models/claude": {"models": [{"id": "group/coding", "name": "编程组演示", "group": "groups", "inUse": True}]},
    "/api/gateway/trace": {"seq": 1, "routes": [], "totals": {}},
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, data, status=200):
        encoded = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path == "/api/state" and "k" in parse_qs(parsed.query):
            self.send_response(303)
            self.send_header("Set-Cookie", "magpie_web_8773=test-session; Path=/; HttpOnly; SameSite=Strict")
            self.send_header("Location", "/api/state")
            self.end_headers()
            return
        if "magpie_web_8773=test-session" not in self.headers.get("Cookie", ""):
            self.reply({"error": "fixture requires session cookie"}, 401)
            return
        if parsed.path == "/":
            body = '<!doctype html><meta name="viewport" content="width=device-width"><h1>控制台联调演示</h1><p>Cookie 会话验证通过</p>'.encode()
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
            return
        if parsed.path not in RESPONSES:
            self.reply({"error": "unknown fixture GET"}, 404)
            return
        self.reply(RESPONSES[parsed.path])

    def do_POST(self):
        if "magpie_web_8773=test-session" not in self.headers.get("Cookie", ""):
            self.reply({"error": "fixture requires session cookie"}, 401); return
        path = urlsplit(self.path).path
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        # Fixture requests contain only demonstration values; no production inputs reach this server.
        with Path("build/ui-api-requests.jsonl").open("a") as output:
            output.write(json.dumps({"path": path, "body": body}, ensure_ascii=False) + "\n")
        if path.startswith("/api/groups/"):
            self.reply(RESPONSES["/api/groups"])
        elif path == "/api/provider/save":
            assert body.get("headers") == PROVIDER["headers"], "Provider save lost custom headers"
            self.reply(RESPONSES["/api/providers"])
        elif path == "/api/masking/values":
            self.reply({"values": {"{{EMAIL_demo}}": "demo@example.invalid"}})
        elif path == "/api/masking/preview":
            self.reply({"text": "预览 {{EMAIL_demo}}", "hits": []})
        elif path == "/api/agent-fast":
            self.reply({"fast": True, "ultra": False})
        elif path.startswith("/api/agent-models/"):
            self.reply(RESPONSES["/api/agent-models/claude"])
        elif path == "/api/settings":
            SETTINGS.update(body); self.reply(SETTINGS)
        elif path.startswith("/api/settings/"):
            self.reply(SETTINGS)
        elif path.startswith("/api/caller-keys/"):
            self.reply({"keys": [KEY], "secret": ""})
        elif path.startswith("/api/agents/") or path == "/api/set" or path.startswith("/api/profile/"):
            self.reply(STATE)
        else:
            self.reply({"error": "unknown fixture POST"}, 404)

if __name__ == "__main__":
    Path("build").mkdir(exist_ok=True)
    print("Mock API listening on 127.0.0.1:8773", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8773), Handler).serve_forever()
