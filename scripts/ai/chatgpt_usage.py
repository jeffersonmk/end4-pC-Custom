#!/usr/bin/env python3
"""
ChatGPT plan usage for the cheat sheet "AI usage" tab.

Reads the Codex / ChatGPT desktop login (~/.codex/auth.json, or
$CODEX_HOME/auth.json) and asks chatgpt.com how much of the plan's usage
limits is used (the same numbers Codex shows in /status).

Prints one JSON object in the same shape as claude_usage.py:
  {"ok": true, "provider": "chatgpt", "plan", "limits": [...], "extra", "breakdown"}
  {"ok": false, "provider": "chatgpt", "error": code}
Error codes: no_credentials, api_key_login, expired, unauthorized, network, bad_response.

Safety:
- The token is only read in this process and sent only to chatgpt.com.
  It never goes on a command line, into the environment or into the output.
- The token is never refreshed here (that would rotate the app's login);
  when it expires the tab asks you to open Codex / ChatGPT once.
- Unofficial endpoint (the one Codex uses), so it may change without notice.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import NoReturn

USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
PROVIDER = "chatgpt"


def auth_path():
    base = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
    return os.path.join(base, "auth.json")


def fail(code, **extra) -> NoReturn:
    print(json.dumps({"ok": False, "provider": PROVIDER, "error": code, **extra}))
    sys.exit(0)


def jwt_claims(token):
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part))
    except (IndexError, ValueError):
        return {}


def window_name(seconds):
    if not seconds:
        return None
    hours = seconds / 3600
    if abs(hours - 5) < 0.5:
        return "5-hour window"
    days = round(hours / 24)
    if days == 1:
        return "Daily window"
    if days == 7:
        return "Weekly window"
    if 28 <= days <= 31:
        return "Monthly window"
    return f"{days}-day window" if days > 1 else f"{round(hours)}-hour window"


def iso(ts):
    if not isinstance(ts, (int, float)):
        return None
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def limit_entry(key, title, raw):
    if not isinstance(raw, dict) or raw.get("used_percent") is None:
        return None
    return {
        "key": key,
        "title": title,
        "subtitle": window_name(raw.get("limit_window_seconds")),
        "percent": raw.get("used_percent"),
        "resetsAt": iso(raw.get("reset_at")),
    }


def main():
    try:
        with open(auth_path()) as f:
            auth = json.load(f)
    except (OSError, ValueError):
        fail("no_credentials")
    tokens = auth.get("tokens") or {}
    token = tokens.get("access_token")
    if not token:
        # Logged in with an API key instead of a ChatGPT account: no plan limits
        fail("api_key_login" if auth.get("OPENAI_API_KEY") else "no_credentials")
    exp = jwt_claims(token).get("exp")
    if isinstance(exp, (int, float)) and exp < time.time():
        fail("expired")

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "end4-pC-Custom",
    }
    if tokens.get("account_id"):
        headers["ChatGPT-Account-Id"] = tokens["account_id"]
    try:
        with urllib.request.urlopen(urllib.request.Request(USAGE_URL, headers=headers), timeout=12) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        fail("unauthorized" if e.code in (401, 403) else "network", status=e.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("network")
    except ValueError:
        fail("bad_response")
    finally:
        token = None
        headers = None

    if not isinstance(data, dict):
        fail("bad_response")

    limits = []
    rate = data.get("rate_limit") or {}
    for key, title in (("primary_window", "Codex limit"), ("secondary_window", "Codex limit")):
        entry = limit_entry(key, title, rate.get(key))
        if entry:
            limits.append(entry)
    review = (data.get("code_review_rate_limit") or {})
    entry = limit_entry("code_review", "Code review", review.get("primary_window"))
    if entry:
        limits.append(entry)
    for i, extra_limit in enumerate(data.get("additional_rate_limits") or []):
        if isinstance(extra_limit, dict):
            name = extra_limit.get("limit_name") or extra_limit.get("metered_feature") or f"Limit {i + 1}"
            entry = limit_entry(f"additional_{i}", name, (extra_limit.get("rate_limit") or {}).get("primary_window"))
            if entry:
                limits.append(entry)

    credits = data.get("credits") or {}
    balance = credits.get("balance")
    try:
        balance = float(balance) if balance is not None else None
    except (TypeError, ValueError):
        balance = None

    print(json.dumps({
        "ok": True,
        "provider": PROVIDER,
        "fetchedAt": int(time.time()),
        "plan": data.get("plan_type"),
        "limitReached": bool(rate.get("limit_reached")),
        "limits": limits,
        "extra": {
            "kind": "credits",
            "enabled": bool(credits.get("has_credits") or credits.get("unlimited")),
            "unlimited": bool(credits.get("unlimited")),
            "balance": balance,
            "spent": None,
            "limit": None,
            "currency": None,
        },
        "breakdown": [],
    }))


if __name__ == "__main__":
    main()
