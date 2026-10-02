#!/usr/bin/env python3
"""
Claude plan usage for the cheat sheet "AI usage" tab.

Reads the Claude Code login (~/.claude/.credentials.json, or
$CLAUDE_CONFIG_DIR/.credentials.json) and asks claude.ai how much of the
plan limits is used: current 5-hour session, weekly limit, per-model weekly
limits, extra-usage spend and the weekly breakdown per product.

Prints one JSON object in the same shape as chatgpt_usage.py:
  {"ok": true, "provider": "claude", "plan", "limits": [...], "extra", "breakdown"}
  {"ok": false, "provider": "claude", "error": code}
Error codes: no_credentials, expired, unauthorized, network, bad_response.

Safety:
- The token is only read in this process and sent only to api.anthropic.com.
  It never goes on a command line, into the environment or into the output.
- The token is never refreshed here (that would rotate Claude Code's login);
  when it expires the tab asks you to open Claude Code once.
- This uses the same unofficial endpoint as Claude Code's /usage screen, so it
  may change without notice.
"""
import json
from typing import NoReturn
import os
import sys
import time
import urllib.error
import urllib.request

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
PROVIDER = "claude"


def credentials_path():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, ".credentials.json")


def fail(code, **extra) -> NoReturn:
    print(json.dumps({"ok": False, "provider": PROVIDER, "error": code, **extra}))
    sys.exit(0)


def limit_entry(key, title, subtitle, raw):
    if not isinstance(raw, dict) or raw.get("utilization") is None:
        return None
    return {"key": key, "title": title, "subtitle": subtitle,
            "percent": raw.get("utilization"), "resetsAt": raw.get("resets_at")}


def main():
    try:
        with open(credentials_path()) as f:
            oauth = json.load(f).get("claudeAiOauth") or {}
    except (OSError, ValueError):
        fail("no_credentials")
    token = oauth.get("accessToken")
    if not token:
        fail("no_credentials")
    expires = oauth.get("expiresAt")
    if isinstance(expires, (int, float)) and expires / 1000 < time.time():
        fail("expired")

    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
        "User-Agent": "end4-pC-Custom",
    })
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        fail("unauthorized" if e.code in (401, 403) else "network", status=e.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("network")
    except ValueError:
        fail("bad_response")
    finally:
        token = None

    if not isinstance(data, dict):
        fail("bad_response")

    limits = [l for l in (
        limit_entry("session", "Current session", "5-hour window", data.get("five_hour")),
        limit_entry("weekly", "Weekly limit", "All models", data.get("seven_day")),
        limit_entry("weekly_opus", "Weekly · Opus", "Opus only", data.get("seven_day_opus")),
        limit_entry("weekly_sonnet", "Weekly · Sonnet", "Sonnet only", data.get("seven_day_sonnet")),
    ) if l]

    extra = data.get("extra_usage") or {}
    spend = data.get("spend") or {}
    used = spend.get("used") or {}
    exponent = used.get("exponent", 2) or 0
    spent = used.get("amount_minor")
    limit = spend.get("limit") if isinstance(spend.get("limit"), dict) else None

    breakdown = (data.get("seven_day_breakdown") or {}).get("rows") or []

    print(json.dumps({
        "ok": True,
        "provider": PROVIDER,
        "fetchedAt": int(time.time()),
        "plan": oauth.get("subscriptionType"),
        "limitReached": any((l.get("percent") or 0) >= 100 for l in limits),
        "limits": limits,
        "extra": {
            "kind": "spend",
            "enabled": bool(extra.get("is_enabled") or spend.get("enabled")),
            "unlimited": False,
            "balance": None,
            "spent": spent / (10 ** exponent) if isinstance(spent, (int, float)) else None,
            "limit": (limit.get("amount_minor") / (10 ** (limit.get("exponent", 2) or 0)))
                     if limit and isinstance(limit.get("amount_minor"), (int, float)) else None,
            "currency": used.get("currency") or "USD",
        },
        "breakdown": [
            {"name": r.get("display_name") or r.get("key"), "percent": r.get("percent") or 0}
            for r in breakdown if isinstance(r, dict)
        ],
    }))


if __name__ == "__main__":
    main()
