import json
from pathlib import Path

rows = [json.loads(line) for line in Path("build/ui-api-requests.jsonl").read_text().splitlines()]
def request(path):
    matches = [row["body"] for row in rows if row["path"] == path]
    assert matches, f"UI did not call {path}"
    return matches[-1]
provider = request("/api/provider/save")
assert provider["headers"] == {"X-Project": "test"}
assert provider["models"] == ["gpt-demo"]
assert provider["contexts"] == {"gpt-demo": 128000}
group = request("/api/groups/save")
assert group["members"] == ["demo/gpt-demo"]
assert group["rules"][0]["where"] == [{"field": "tokens", "op": "gte", "value": "32000"}]
assert request("/api/groups/copy")["id"] == "coding"
assert request("/api/masking/values")["ps"] == ["{{EMAIL_demo}}"]
print("PASS: UI saves preserve provider headers, model IDs and contexts; routing advanced conditions; group copy; explicit masking reveal")
