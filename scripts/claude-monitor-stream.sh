#!/bin/bash
# Claude Code Monitor tool wrapper for amq.
#
# Spawned by Claude Code when the amq-cli plugin is active (via the `monitors`
# key in .claude-plugin/plugin.json). Loops `amq monitor` and emits one line
# per new AMQ message on stdout — each line becomes a Monitor tool event that
# streams into Claude's conversation transcript.
#
# This is the Claude Code replacement for `amq wake --me claude` — it avoids
# TIOCSTI terminal injection entirely (see issue #95).

set -uo pipefail

ME="${AM_ME:-claude}"

while true; do
    # --timeout 0: block until a message arrives (no periodic exit).
    # --include-body: carry full body for model context.
    # --json: structured output we reshape into one line per message.
    if ! result=$(amq monitor --me "$ME" --timeout 0 --include-body --json 2>/dev/null); then
        # Transient error (missing root, perms, etc.) — back off and retry.
        sleep 5
        continue
    fi

    # Reshape drained-messages payload into one stdout line per message.
    # Plain text lines are what Claude Code's Monitor tool renders as events.
    # Use -c (not heredoc) so stdin stays available for the JSON pipe.
    printf '%s' "$result" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    if data.get("event") != "messages":
        sys.exit(0)

    me = sys.argv[1]
    session = data.get("session", "")
    prefix = f"[AMQ {session}]" if session else "[AMQ]"

    for msg in data.get("drained", []):
        if msg.get("parse_error"):
            continue
        from_h = msg.get("from", "unknown")
        subj = msg.get("subject") or "(no subject)"
        prio = msg.get("priority", "normal")
        if len(subj) > 80:
            subj = subj[:77] + "..."
        print(f"{prefix} {from_h} → {me} ({prio}): {subj}", flush=True)
except (json.JSONDecodeError, KeyError, TypeError):
    pass
' "$ME"
done
