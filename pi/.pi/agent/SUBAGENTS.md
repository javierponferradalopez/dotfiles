# Sub-agents in pi

Skills ask for sub-agents in words that fit any harness. In pi, the `subagent` tool
of `pi-subagents` does each one. If your tool list shows `subagents_enable` and not
`subagent`, call `subagents_enable` first.

| The skill asks for | Call |
|---|---|
| A sub-agent (foreground, can edit) | `subagent({ agent: "skill-runner", async: false, task: <brief> })` |
| A read-only sub-agent | `subagent({ agent: "skill-reader", async: false, task: <brief> })` |
| Answer the **same** sub-agent | `subagent({ action: "resume", id: <runId>, message: <answer> })`, then `bg_wait({ id: <new runId> })` |
| Sub-agents in parallel | `subagent({ async: false, options: { script: "return runs.all([{ key, agent, task }, ...])" } })` |
| A background sub-agent | `subagent({ agent: "skill-runner", async: true, task: <brief> })` |
| A sub-agent that reads the web | `subagent({ agent: "skill-researcher", async: true, task: <brief> })` — always in the background: a foreground child does not load the web tools |

- **`runId`** — a foreground result shows only `Mission: <mission-id>`, and `resume`
  rejects that id. Get the run id with
  `jq -r '.runs[-1].runId' ~/.pi/agent/missions/projects/*/<mission-id>.json`.
- **Resume** — it always runs in the background and returns a new run id. After
  `bg_wait` on that id, read the reply from
  `~/.pi/agent/sessions/<session-dir>/subagent-artifacts/<new-runId>_<agent>_output.md`.
  `<session-dir>` is the folder that holds the current session file. To answer the
  sub-agent again, resume the new run id.
- **Parallel** — put the script in `options.script` and leave out `workflow`. Use
  `skill-reader` for a lane that only reads, and `skill-runner` for a lane that
  edits. Give each lane a different `key`.
- **Background** — continue your work; the result comes back as a notification. Use
  `bg_wait` only when this turn needs the result.
- **A brief that says "invoke `/<skill>`"** works as written: `skill-runner` sees the
  skill catalog and reads that `SKILL.md`.
