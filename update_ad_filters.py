"""Convert only unambiguous EasyList domain rules to WebKit rules.
Unsupported scoped/regex rules are excluded, never broadened.
Derived data: CC BY-SA 3.0, The EasyList authors, https://easylist.to/.
"""
import json
import re
import urllib.request
from pathlib import Path
from datetime import datetime, timezone

url = "https://easylist-downloads.adblockplus.org/easylist.txt"
text = urllib.request.urlopen(url, timeout=60).read().decode("utf-8")
# Omit a block domain when any domain-scoped/path exception might apply to it.
# This conservative subset avoids broadening rules by dropping their exceptions.
exception_domains = set()
for line in text.splitlines():
    match = re.match(r"@@\|\|([a-z0-9.-]+)", line)
    if match:
        pieces = match[1].split(".")
        for index in range(len(pieces) - 1):
            exception_domains.add(".".join(pieces[index:]))
rules = []
seen = set()
for line in text.splitlines():
    match = re.fullmatch(r"\|\|([a-z0-9.-]+)\^(\$third-party)?", line)
    if not match:
        continue
    domain, third_party = match.groups()
    if "." not in domain or domain in exception_domains or (domain, third_party) in seen:
        continue
    seen.add((domain, third_party))
    trigger = {"url-filter": "^https?://([^/]+\\.)?" + domain.replace(".", "\\.") + "[:/]"}
    if third_party:
        trigger["load-type"] = ["third-party"]
    rules.append({"trigger": trigger, "action": {"type": "block"}})
# Exact, unscoped domain exceptions are placed after blocking rules.
for line in text.splitlines():
    match = re.fullmatch(r"@@\|\|([a-z0-9.-]+)\^", line)
    if match:
        rules.append({"trigger": {"url-filter": "^https?://([^/]+\\.)?" + match[1].replace(".", "\\.") + "[:/]"}, "action": {"type": "ignore-previous-rules"}})
print("Parsed domain rules:", len(rules))
assert 1000 < len(rules) < 49000, "Unexpected list size; review source format before updating"
Path("BrowserAdDomains.json").write_text(json.dumps(rules, separators=(",", ":")), encoding="utf-8")
Path("Licenses/EasyList-Attribution.txt").write_text(
    "Jiza advertising-domain filters\n\nSource: The EasyList authors (https://easylist.to/).\n"
    "Source list: " + url + "\nRetrieved: " + datetime.now(timezone.utc).date().isoformat() + "\n"
    "Derived domain rules: " + str(len(rules)) + "\n\n"
    "This derived filter data is licensed under Creative Commons Attribution-ShareAlike 3.0 Unported.\n"
    "License: https://creativecommons.org/licenses/by-sa/3.0/\n"
    "Changes: only exact domain block rules, third-party-only domain rules and exact unscoped domain exceptions "
    "are converted to WebKit JSON. Other EasyList syntax is omitted. This is a subset, not the complete EasyList engine.\n"
    "No endorsement by the EasyList authors is implied.\n", encoding="utf-8")
print(f"Generated {len(rules)} domain rules")
