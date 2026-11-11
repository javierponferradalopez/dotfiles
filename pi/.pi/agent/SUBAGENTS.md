# Sub-agents in pi

Skills ask for sub-agents in words that fit any harness. In pi, the `Agent` tool of
`@tintinweb/pi-subagents` does each one. Each child gets all tools of a normal pi
session: built-in tools, extension tools, and MCP servers through `codemode`.

| The skill asks for | Call |
|---|---|
| A sub-agent (foreground, can edit) | `Agent({ subagent_type: "skill-runner", name: <handle>, description: <3-5 words>, prompt: <brief>, run_in_background: false })` |
| A read-only sub-agent | The same call with `subagent_type: "skill-reader"` |
| A sub-agent that reads the web | The same call with `subagent_type: "skill-runner"` |
| Answer the **same** sub-agent | `Agent({ subagent_type: <same type>, resume: <agent ID>, description: <3-5 words>, prompt: <answer>, run_in_background: false })` |
| A background sub-agent | The first call with `run_in_background: true` |
| Sub-agents in parallel | One background call for each lane, all in the same message |

- **`name`** — give each sub-agent a unique handle, such as `build-t12`. Use it with
  `get_subagent_result` and `steer_subagent`.
- **Agent ID** — `resume` accepts only the agent ID, not the handle. A foreground
  result does not show the ID. Get it from the `Agent:` line of
  `get_subagent_result({ agent_id: <handle> })`. A background call returns the ID
  at once.
- **Background** — continue your work; a notification with a preview comes back when
  the sub-agent completes. Get the full text with
  `get_subagent_result({ agent_id: <handle> })`. When this turn needs the result,
  add `wait: true`.
- **Parallel** — give each lane a different `name`. Use `skill-reader` for a lane
  that only reads, and `skill-runner` for a lane that edits. For a fixed script of
  many lanes, use the `SubagentWorkflow` tool.
- **A brief that says "invoke `/<skill>`"** works as written: `skill-runner` sees the
  skill catalog and reads that `SKILL.md`.
