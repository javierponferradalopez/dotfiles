// Give an unnamed session a short title, like the ai-title of Claude Code.
// The herdr auto-title plugin reads the session_info entry that this writes.
// The terminal title is the session name only, because the herdr agents
// sidebar shows the terminal title and Pi frames it as "π - <name> - <dir>".

import { uuidv7 } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const MAX_ATTEMPTS = 3;
const MAX_CHARS = 4000;
// A small model, because the session model can be expensive (Opus) for a title.
const TITLE_MODEL: [string, string] = ["anthropic", "claude-haiku-5-5"];

const textOf = (content: unknown): string => {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((c: any) => c?.type === "text" && typeof c.text === "string")
		.map((c: any) => c.text)
		.join("\n");
};

export default function (pi: ExtensionAPI) {
	let attempts = 0;
	let busy = false;

	// Pi sets its own title after these events, so set ours on the next tick.
	const showName = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		setTimeout(() => {
			const name = pi.getSessionName();
			if (name) ctx.ui.setTitle(name);
		}, 50);
	};

	pi.on("session_start", async (_event, ctx) => {
		attempts = 0;
		showName(ctx);
	});

	pi.on("session_info_changed", async (_event, ctx) => {
		showName(ctx);
	});

	pi.on("agent_settled", async (_event, ctx) => {
		if (busy || attempts >= MAX_ATTEMPTS || pi.getSessionName()) return;

		const lines: string[] = [];
		for (const entry of ctx.sessionManager.getBranch() as any[]) {
			const role = entry.type === "message" ? entry.message?.role : undefined;
			if (role !== "user" && role !== "assistant") continue;
			const text = textOf(entry.message.content).trim();
			if (text) lines.push(`${role === "user" ? "User" : "Assistant"}: ${text}`);
		}
		const conversation = lines.join("\n\n").slice(0, MAX_CHARS);
		if (!conversation) return;

		const model = ctx.modelRegistry.find(...TITLE_MODEL) ?? ctx.model;
		if (!model) return;

		busy = true;
		attempts++;
		try {
			const response = await ctx.modelRegistry.complete(
				model,
				{
					messages: [
						{
							role: "user",
							content: [
								{
									type: "text",
									text: [
										"Write a title for this coding session, in the language the user writes in.",
										"Use 2 to 6 words. Name the task, not the greeting.",
										"Reply with the title only: no quotes, no final period.",
										"If the conversation does not show a task yet, reply SKIP.",
										"",
										"<conversation>",
										conversation,
										"</conversation>",
									].join("\n"),
								},
							],
							timestamp: Date.now(),
						},
					],
				},
				{ cacheRetention: "none", sessionId: uuidv7() },
			);
			const title = textOf(response.content)
				.split("\n")[0]
				.trim()
				.replace(/^["'«“]|["'»”.]$/g, "")
				.slice(0, 60);
			if (title && title !== "SKIP" && !pi.getSessionName()) pi.setSessionName(title);
		} catch {
			// A failed title is not worth an error in the session.
		} finally {
			busy = false;
		}
	});
}
