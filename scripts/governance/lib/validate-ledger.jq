# ABOUTME: jq filter that validates evidence coverage against a requirement map.
# ABOUTME: Input: {"requirements": [...], "evidence": {"REQ-01": "text"|null, ...}}
# ABOUTME: Outputs JSON array of {req_id, what, status: "GREEN"|"RED", detail}.
# ABOUTME: GREEN = non-empty evidence string present. RED = null/empty/missing.
# ABOUTME: Used by post-agent-audit.sh to assess subagent completion coverage.

.requirements as $reqs | .evidence as $ev |
[
  $reqs[] | {
    req_id: .req_id,
    what: .what,
    status: (
      if ($ev[.req_id] // null) != null and (($ev[.req_id] | type) == "string") and (($ev[.req_id] | length) > 0)
      then "GREEN"
      else "RED"
      end
    ),
    detail: (
      if ($ev[.req_id] // null) != null and (($ev[.req_id] | type) == "string") and (($ev[.req_id] | length) > 0)
      then "evidence found"
      else "NO EVIDENCE in agent output"
      end
    )
  }
]
