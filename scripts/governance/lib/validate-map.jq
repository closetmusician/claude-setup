# ABOUTME: jq filter that validates a requirement map JSON structure.
# ABOUTME: Expects input with task_id (string) and requirements (array).
# ABOUTME: Each requirement must have: req_id, what, done_when, escalate_if, source.
# ABOUTME: Outputs "valid" on success; outputs error message and halts on failure.
# ABOUTME: Used by pre-agent-gate.sh to validate governance context in subagent prompts.

def assert(cond; msg): if cond then . else msg | halt_error(1) end;

. | assert(type == "object"; "requirement map must be a JSON object")
  | assert(.task_id != null and (.task_id | type) == "string" and (.task_id | length) > 0;
      "task_id must be a non-empty string")
  | assert(.requirements != null and (.requirements | type) == "array" and (.requirements | length) > 0;
      "requirements must be a non-empty array")
  | .requirements[] |
    assert(.req_id != null and (.req_id | type) == "string" and (.req_id | length) > 0;
      "each requirement must have a non-empty req_id")
    | assert(.what != null and (.what | type) == "string" and (.what | length) > 0;
        "each requirement must have a non-empty what")
    | assert(.done_when != null and (.done_when | type) == "string" and (.done_when | length) > 0;
        "each requirement must have a non-empty done_when")
    | assert(.escalate_if != null and (.escalate_if | type) == "string" and (.escalate_if | length) > 0;
        "each requirement must have a non-empty escalate_if")
    | assert(.source != null and (.source | type) == "string" and (.source | length) > 0;
        "each requirement must have a non-empty source")
| "valid"
