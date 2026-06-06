#!/usr/bin/env python3
"""PostToolUse hook -- minden tool-hivast elkuld a marveen /api/tool-log
endpointra (tool_call_log tabla). Fail-silent: barmilyen hiba eseten csendben
kilep, sosem blokkolja vagy tori meg az agentet.

Bekotes (.claude/settings.json es agents/*/.claude/settings.json):
  "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command",
     "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/hooks/tool-log-capture.py\"",
     "timeout": 10 }]}]
"""
import json
import os
import sys
import urllib.request


def main() -> None:
    try:
        raw = sys.stdin.read()
        ev = json.loads(raw) if raw.strip() else {}
    except Exception:
        return

    session_id = ev.get("session_id") or "unknown"
    tool_name = ev.get("tool_name") or "unknown"
    tool_input = ev.get("tool_input")
    tool_response = ev.get("tool_response")

    # input_summary -- kompakt, csonkolt reprezentacio (a Bash command a legbeszedesebb)
    try:
        if isinstance(tool_input, dict):
            summary = (
                tool_input.get("command")
                or tool_input.get("file_path")
                or tool_input.get("pattern")
                or json.dumps(tool_input, ensure_ascii=False)
            )
        else:
            summary = str(tool_input) if tool_input is not None else ""
    except Exception:
        summary = ""
    summary = (summary or "")[:300]

    # success -- best-effort a tool_response alapjan
    success = True
    try:
        if isinstance(tool_response, dict) and (
            tool_response.get("is_error") or tool_response.get("error")
        ):
            success = False
    except Exception:
        pass

    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        with open(os.path.join(project, "store", ".dashboard-token")) as f:
            token = f.read().strip()
    except Exception:
        return
    if not token:
        return

    port = os.environ.get("MARVEEN_DASHBOARD_PORT", "3420")
    body = json.dumps(
        {
            "session_id": session_id,
            "tool_name": tool_name,
            "input_summary": summary,
            "success": success,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"http://localhost:{port}/api/tool-log",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        return


if __name__ == "__main__":
    main()
