/**
 * Permissions
 *
 * Pi does not ask before a tool call. This extension adds these rules: it
 * blocks access to secret files, it blocks `rm -rf`, and it asks before
 * `git push`.
 */

import * as path from "node:path";
import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";

const SECRET_PATHS: RegExp[] = [
	/(^|\/)\.env[^/]*$/,
	/(^|\/)env\.php[^/]*$/,
	/\.pem$/,
	/\.key$/,
	/(^|\/)secrets\//,
	/(^|\/)credentials\//,
	/(^|\/)\.aws\//,
	/(^|\/)\.ssh\//,
	/(^|\/)config\/database\.yml$/,
];

const BLOCKED_COMMANDS: RegExp[] = [/\brm\s+-rf\b/];

const CONFIRMED_COMMANDS: RegExp[] = [/\bgit\s+push\b/];

function isSecret(filePath: string, cwd: string): boolean {
	const absolute = path.resolve(cwd, filePath.replace(/^~(?=\/)/, process.env.HOME ?? "~"));
	return SECRET_PATHS.some((pattern) => pattern.test(absolute));
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (
			isToolCallEventType("read", event) ||
			isToolCallEventType("edit", event) ||
			isToolCallEventType("write", event)
		) {
			if (isSecret(event.input.path, ctx.cwd)) {
				return { block: true, reason: `Access to "${event.input.path}" is not permitted` };
			}
			return undefined;
		}

		if (!isToolCallEventType("bash", event)) return undefined;

		const command = event.input.command;
		if (BLOCKED_COMMANDS.some((pattern) => pattern.test(command))) {
			return { block: true, reason: "This command is not permitted" };
		}

		if (CONFIRMED_COMMANDS.some((pattern) => pattern.test(command))) {
			if (!ctx.hasUI) {
				return { block: true, reason: "This command needs approval and there is no UI" };
			}
			const approved = await ctx.ui.confirm("Run this command?", command);
			if (!approved) {
				return { block: true, reason: "The user did not approve this command" };
			}
		}

		return undefined;
	});
}
