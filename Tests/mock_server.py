import os
"""Local-only API fixture for iOS UI tests. Never contacts an upstream service."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

PROXY = {
    "id": "px-hk",
    "name": "香港节点演示",
    "url": "socks5://127.0.0.1:7890",
    "user": "demo",
    "hasPass": True,
    "uses": [{"where": "global"}],
    "check": {"ok": True, "ms": 38, "ip": "203.0.113.10", "loc": "HK"}
}
SETTINGS = {
    "version": "test-fixture",
    "theme": "system",
    "lang": "zh",
    "currency": "usd",
    "totalCurrency": "usd",
    "chineseUnits": True,
    "dayStart": 0,
    "redact": True,
    "redactPersonal": True,
    "redactShape": False,
    "redactRules": [{"kind": "CORP", "regex": "INTERNAL_[A-Z]+"}],
    "redactAllow": ["dev@company.com"],
    "redactRouteTo": "",
    "lan": False,
    "port": 3425,
    "allowIPs": ["192.168.1.0/24"],
    "corsOrigins": ["https://console.example.invalid"],
    "proxy": "@px-hk",
    "pluginProxy": "",
    "updateProxy": "direct",
    "proxyNow": "socks5://127.0.0.1:7890",
    "proxySource": "settings",
    "proxies": [PROXY],
    "quotaLeft": True,
    "quotaReads": "",
    "usageAlert": 80,
    "balanceAlert": 5.0,
    "resetReminder": 30,
    "turnDoneAlert": 60,
    "maskAlert": True,
    "busyLoad": 70,
    "fullContext": False,
    "compactAt": 272000,
    "contextCap": 200000,
    "contextCapAll": False,
    "disabledModels": [],
    "searchAll": True,
    "searchCount": 5,
    "searchAPIs": [{"vendor": "tavily", "name": "Tavily", "key": "tvly-••••-1001", "ready": True, "keys": 1, "off": False}],
    "claudeCache": [
        {"knob": "cache_ttl", "value": "5m", "locked": ""},
        {"knob": "subagent_cache_ttl", "value": "5m", "locked": ""}
    ],
    "claudeAttribution": "on"
}
PROVIDER = {
    "id": "demo",
    "name": "OpenAI 演示",
    "ready": True,
    "chat": "https://api.example.invalid/v1",
    "preset": "custom",
    "routing": "rotate",
    "headers": {"X-Project": "test"},
    "chosen": ["gpt-demo"],
    "contexts": {"gpt-demo": 128000},
    "keyList": [
        {"id": "k1", "name": "主 Key", "masked": "test-••••-0001", "active": True, "on": True},
        {"id": "k2", "name": "备用 Key", "masked": "test-••••-0002", "active": False, "on": True, "weight": 2}
    ],
    "models": [
        {"id": "gpt-demo", "name": "GPT 演示模型", "on": True, "context": 128000, "images": True, "efforts": ["low", "medium", "high"]}
    ],
    "exposed": 1
}
AGY_PROVIDER = {
    "id": "antigravity",
    "name": "Antigravity (谷歌反重力)",
    "ready": True,
    "routing": "order",
    "models": [
        {"id": "gemini-2.5-pro", "name": "Gemini 2.5 Pro", "on": True, "context": 1000000}
    ],
    "exposed": 1,
    "account": {
        "agent": "antigravity",
        "agentName": "Antigravity",
        "user": "demo1@gmail.com",
        "plan": "Google AI Pro",
        "logins": [
            {"agent": "antigravity", "user": "demo1@gmail.com", "plan": "Google AI Pro", "active": True, "on": True},
            {"agent": "antigravity", "user": "demo2@gmail.com", "plan": "free", "active": False, "on": True}
        ]
    },
    "accountWeights": {"demo1@gmail.com": 2, "demo2@gmail.com": 1},
    "accountRests": {
        "demo2@gmail.com": [
            {"why": "rate", "status": 429, "until": "2026-11-17T22:15:00+08:00", "rate": True, "key": "antigravity#demo2@gmail.com"}
        ]
    }
}
PLUGIN_SUB = {
    "id": "trae-cn",
    "pid": "trae-cn",
    "name": "Trae CN",
    "icon": "trae",
    "spec": "@magpie-community/trae-cn",
    "methods": [{"type": "oauth", "label": "Browser", "labels": {"zh": "浏览器 OAuth 授权"}}],
    "signedIn": False,
    "models": 2,
    "importable": False
}
SIGNIN_STATE = {
    "id": "s1",
    "agent": "antigravity",
    "url": "https://accounts.google.com/o/oauth2/v2/auth?client_id=demo&redirect_uri=http://127.0.0.1:54321/callback",
    "state": "waiting",
    "pasteCallback": True,
    "callbackPort": 54321,
    "linkOnly": True
}
LOGIN_USAGE = {
    "demo1@gmail.com": {
        "provider": "antigravity",
        "name": "Antigravity",
        "icon": "antigravity-color",
        "plan": "Google AI Pro",
        "user": "demo1@gmail.com",
        "windows": [
            {"name": "5小时额度", "used": 28.0, "capId": "5h"},
            {"name": "周额度", "used": 14.0, "capId": "7d"}
        ]
    },
    "demo2@gmail.com": {
        "provider": "antigravity",
        "name": "Antigravity",
        "icon": "antigravity-color",
        "plan": "free",
        "user": "demo2@gmail.com",
        "windows": [
            {"name": "5小时额度", "used": 62.0, "capId": "5h"}
        ]
    }
}
PRESET = {
    "id": "deepseek",
    "name": "DeepSeek",
    "short": "DeepSeek",
    "kind": "vendor",
    "chat": "https://api.deepseek.com/v1",
    "anthropic": "https://api.deepseek.com/anthropic"
}
GROUP = {
    "id": "coding",
    "name": "编程组演示",
    "ref": "group/coding",
    "members": ["demo/gpt-demo"],
    "routing": "manual",
    "ready": True,
    "picked": "demo/gpt-demo",
    "rules": [{"use": "demo/gpt-demo", "tokens": 32000, "where": [{"field": "tokens", "op": "gte", "value": "32000"}]}]
}
STATE = {
    "settings": SETTINGS,
    "served": 1,
    "agents": [
        {
            "id": "claude",
            "name": "Claude Code 演示",
            "wired": True,
            "path": "~/.claude/settings.json",
            "fields": [
                {
                    "key": "model",
                    "label": "主模型",
                    "value": "group/coding",
                    "options": [{"value": "group/coding", "label": "编程组演示", "ref": "group/coding", "fastFor": "claude"}]
                }
            ]
        }
    ],
    "profiles": [{"name": "开发方案", "summary": "Claude → 编程组", "inUse": True}]
}
KEY = {
    "id": "caller-demo",
    "name": "移动端演示",
    "masked": "test-••••-9001",
    "limit": {"period": "week", "tokens": 1000000, "cost": 10},
    "used": {"period": "week", "tokens": 12345, "cost": .25, "reset": "2026-11-23T00:00:00+08:00"}
}
RECORD = {
    "key": "1001",
    "t": "2026-11-17T15:30:00+08:00",
    "what": "chat",
    "model": "gpt-demo",
    "n": 1,
    "values": [{"p": "{{EMAIL_demo}}", "k": "EMAIL", "b": "personal", "l": 17, "n": 1, "known": True}]
}
USAGE = {
    "calls": 126,
    "errors": 2,
    "input": 125000,
    "output": 42000,
    "cost": .75,
    "bucket": "hour",
    "series": [
        {"label": f"{hour:02d}:00", "calls": calls, "input": calls * 900, "output": calls * 300, "cost": calls * .005}
        for hour, calls in zip(range(8, 16), [3, 8, 21, 15, 11, 26, 30, 12])
    ]
}
AUTOBACKUP = {
    "on": True,
    "hours": 24,
    "keep": 7,
    "dir": "~/.config/magpie/auto-backups",
    "custom": False,
    "signIns": False,
    "passphrase": True,
    "backups": [
        {
            "name": "magpie-20261117-080000-auto.json",
            "made": "2026-11-17T08:00:00+08:00",
            "reason": "auto",
            "size": 8192,
            "providers": 1,
            "library": True
        }
    ]
}
DAVSYNC = {
    "on": True,
    "url": "https://dav.example.invalid/magpie",
    "user": "demo@example.invalid",
    "passwordSet": True,
    "passphraseSet": True,
    "keys": True,
    "agents": True,
    "kind": "webdav",
    "library": True,
    "memory": True,
    "providers": True,
    "settings": True,
    "profiles": True,
    "usage": True,
    "signIns": False,
    "last": "2026-11-17T18:00:00+08:00",
    "auto": 15,
    "followServer": False,
    "undo": True
}
TUNE = {
    "days": 7,
    "gateway": False,
    "agents": [
        {
            "agent": "claude",
            "calls": 126,
            "advice": [
                {
                    "knob": "compact",
                    "model": "claude-sonnet-4-5",
                    "setting": {"value": "200000", "source": "long", "ours": True, "take": False},
                    "compact": {
                        "model": "claude-sonnet-4-5",
                        "current": 200000,
                        "window": 200000,
                        "best": 160000,
                        "cost": 14.2,
                        "low": 10.8
                    }
                },
                {
                    "knob": "cache_ttl",
                    "setting": {"value": "5m", "source": "settings", "ours": False, "take": False},
                    "ttl": {
                        "current": "5m",
                        "best": "1h",
                        "cost": 12.0,
                        "low": 8.5,
                        "short": 12.0,
                        "hour": 8.5
                    }
                }
            ]
        }
    ]
}
MODEL_PRICE = {
    "model": "gpt-demo",
    "price": {"input": 2.5, "output": 10.0, "cache_read": 0.25, "cache_write": 3.125},
    "maker": {"input": 2.5, "output": 10.0, "cache_read": 0.25, "cache_write": 3.125}
}
PRIVACY_MODEL = {
    "on": True,
    "chosen": True,
    "id": "astrlink-guard",
    "name": "AstrLink Guard",
    "installed": True,
    "downloading": False,
    "minScore": 0.85,
    "defaultScore": 0.85
}
RESPONSES = {
    "/api/state": STATE,
    "/api/settings": SETTINGS,
    "/api/providers": {"providers": [PROVIDER, AGY_PROVIDER], "presets": [PRESET], "plugins": [PLUGIN_SUB], "gateway": {"running": True, "url": "http://127.0.0.1:3425"}},
    "/api/plugins/listings": {"listings": [
        {"package": "@magpie-community/opencode-zen-free-auth", "name": "OpenCode Zen Free", "icon": "opencode", "providers": ["opencode-zen-free"], "community": True, "summary": {"zh": "使用 public 凭证接入 OpenCode Zen 免费模型"}},
        {"package": "@magpie-community/opencode-agy-cli-auth", "name": "Antigravity (local agy CLI)", "icon": "antigravity-color", "providers": ["agy-cli"], "community": True, "summary": {"zh": "通过本机 agy CLI 安全接入 Google Antigravity"}}
    ]},
    "/api/login/usage": LOGIN_USAGE,
    "/api/signin/s1": SIGNIN_STATE,
    "/api/groups": {
        "groups": [GROUP],
        "models": [{"id": "demo/gpt-demo", "name": "GPT 演示模型", "provider": "demo", "providerName": "OpenAI 演示"}],
        "templates": [{"kind": "coding", "group": GROUP, "why": "自动故障转移"}],
        "defaults": {"sink": True, "firstToken": 45, "patience": 30},
        "found": True
    },
    "/api/usage": USAGE,
    "/api/usage/quotas": [],
    "/api/caller-keys": {"keys": [KEY]},
    "/api/masking/summary": {"requests": 1, "n": 1},
    "/api/masking/records": {"records": [RECORD], "more": False},
    "/api/masking/sent": {"body": "联系 {{EMAIL_demo}}"},
    "/api/agent-models/claude": {"models": [{"id": "group/coding", "name": "编程组演示", "group": "groups", "inUse": True}]},
    "/api/gateway/trace": {"seq": 1, "routes": [], "totals": {}},
    "/api/autobackup": AUTOBACKUP,
    "/api/davsync": DAVSYNC,
    "/api/tune": TUNE,
    "/api/model-price": MODEL_PRICE,
    "/api/privacy-model": PRIVACY_MODEL,
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
        with Path("build/ui-api-requests.jsonl").open("a") as output:
            output.write(json.dumps({"path": path, "body": body}, ensure_ascii=False) + "\n")
        if path.startswith("/api/groups/"):
            self.reply(RESPONSES["/api/groups"])
        elif path == "/api/provider/save" or path.startswith("/api/provider/") or path.startswith("/api/providers/") or path.startswith("/api/keys/"):
            if path == "/api/provider/save" and not body.get("new"):
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
        elif path == "/api/settings/port":
            SETTINGS["port"] = body.get("port", 3425)
            self.reply({"settings": SETTINGS, "port": {"ok": True}})
        elif path == "/api/settings/archive":
            self.reply({"on": bool(body.get("on", False)), "folder": "~/.config/magpie/archive"})
        elif path == "/api/settings":
            SETTINGS.update(body); self.reply(SETTINGS)
        elif path.startswith("/api/settings/"):
            self.reply(SETTINGS)
        elif path == "/api/proxies/test":
            self.reply({"ok": True, "ms": 35, "ip": "203.0.113.10", "loc": "HK"})
        elif path.startswith("/api/proxies/"):
            self.reply(SETTINGS)
        elif path == "/api/backup/export":
            self.reply({"path": "~/Downloads/magpie-2026-11-17.magpie", "providers": 1, "profiles": 1, "agents": 1, "library": True, "signIns": 0})
        elif path == "/api/backup/import":
            self.reply({"providers": 1, "profiles": 1, "agents": 1, "settings": True, "library": True, "memory": 0, "signIns": 0, "signInsLocked": False})
        elif path.startswith("/api/autobackup/"):
            self.reply(AUTOBACKUP)
        elif path.startswith("/api/davsync/"):
            self.reply(DAVSYNC)
        elif path.startswith("/api/tune/"):
            self.reply({"value": body.get("value", "160000"), "source": "long", "ours": True, "take": False})
        elif path == "/api/model-price":
            self.reply({"model": body.get("model", "gpt-demo"), "price": body.get("price"), "maker": MODEL_PRICE["maker"]})
        elif path == "/api/privacy-model":
            self.reply(PRIVACY_MODEL)
        elif path in ("/api/gateway/take-over", "/api/gateway/restart"):
            self.reply({"ok": True})
        elif path == "/api/gateway/pause":
            self.reply({"paused": bool(body.get("on", False)), "agents": ["claude"]})
        elif path == "/api/gateway/unrest":
            self.reply({"lifted": True})
        elif path == "/api/usage/clear" or path == "/api/usage/codex-reset":
            self.reply({"ok": True})
        elif path.startswith("/api/caller-keys/"):
            self.reply({"keys": [KEY], "secret": ""})
        elif path == "/api/signin" or path == "/api/plugin-signin":
            st = dict(SIGNIN_STATE)
            if body.get("agent"):
                st["agent"] = body["agent"]
            self.reply(st)
        elif path == "/api/signin/s1/cancel" or path == "/api/signin/s1/callback":
            self.reply({})
        elif path == "/api/signin/claude-token":
            self.reply({"user": "claude-token-demo"})
        elif path == "/api/signin/import":
            self.reply({"results": [{"user": "imported@gmail.com", "status": "added"}], "providers": RESPONSES["/api/providers"]})
        elif path == "/api/signin/export":
            self.reply({"path": "~/Downloads/magpie-export.json", "accounts": ["demo1@gmail.com"], "skipped": []})
        elif path == "/api/plugin-signin/prompt":
            self.reply({"prompt": None, "inputs": body.get("inputs", {})})
        elif path.startswith("/api/login/") or path.startswith("/api/codex/daemon/"):
            self.reply(RESPONSES["/api/providers"])
        elif path.startswith("/api/agents/") or path == "/api/set" or path.startswith("/api/profile/") or path == "/api/sync":
            self.reply(STATE)
        else:
            self.reply({"error": f"unknown fixture POST: {path}"}, 404)

if __name__ == "__main__":
    Path("build").mkdir(exist_ok=True)
    port = int(os.environ.get("MAGPIE_FIXTURE_PORT", "8773"))
    ThreadingHTTPServer.allow_reuse_address = True
    print(f"Mock API listening on 127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
