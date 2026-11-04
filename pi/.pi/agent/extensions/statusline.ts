/**
 * Status line
 *
 * Replaces the Pi footer with one line about the context window:
 *
 *   model • thinking │ ✍️ context % (window) │ 🎯 tokens/120k %
 *
 * Above the personal limit of 120k tokens the 🎯 changes to 🚨. The colors
 * change at 50%, 70% and 90%. The data comes from Pi, so it works with all
 * providers.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

const PERSONAL_LIMIT = 120_000;

const RESET = "\x1b[0m";
const DIM = "\x1b[2m";
const GREEN = "\x1b[38;2;0;175;80m";
const ORANGE = "\x1b[38;2;255;176;85m";
const YELLOW = "\x1b[38;2;230;200;0m";
const RED = "\x1b[38;2;255;85;85m";
const BLUE = "\x1b[38;2;0;153;255m";
const SEP = ` ${DIM}│${RESET} `;

function colorPct(pct: number): string {
	if (pct >= 90) return RED;
	if (pct >= 70) return YELLOW;
	if (pct >= 50) return ORANGE;
	return GREEN;
}

function formatK(tokens: number): string {
	return tokens >= 1000 ? `${(tokens / 1000).toFixed(1)}k` : `${tokens}`;
}

function formatWindowSize(size: number): string {
	return size >= 1_000_000 ? `${size / 1_000_000}M` : `${Math.round(size / 1000)}k`;
}

export default function(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((_tui, _theme, footerData) => ({
			invalidate() { },
			render(width: number): string[] {
				const usage = ctx.getContextUsage();
				const windowSize = usage?.contextWindow || ctx.model?.contextWindow || 0;
				const known = usage?.tokens != null && windowSize > 0;
				const tokens = usage?.tokens ?? 0;

				const model = ctx.model?.id ?? "no-model";
				const thinking = ctx.model?.reasoning ? ` ${DIM}• ${ctx.thinkingLevel}${RESET}` : "";
				let line = `${BLUE}${model}${RESET}${thinking}${SEP}`;

				if (known) {
					const ctxPct = Math.floor((tokens * 100) / windowSize);
					const personalPct = Math.floor((tokens * 100) / PERSONAL_LIMIT);
					const personalColor = colorPct(personalPct);
					const icon = tokens > PERSONAL_LIMIT ? "🚨" : "🎯";
					line += `✍️ ${colorPct(ctxPct)}${ctxPct}%${RESET} ${DIM}(${formatWindowSize(windowSize)})${RESET}${SEP}`;
					line += `${icon} ${personalColor}${formatK(tokens)}${RESET}${DIM}/120k${RESET} ${personalColor}${personalPct}%${RESET}`;
				} else {
					// After a compaction, Pi knows the tokens again only after the next response.
					line += `${DIM}✍️ ?${windowSize > 0 ? ` (${formatWindowSize(windowSize)})` : ""}${RESET}`;
				}

				const lines = [line];

				// The custom footer replaces the built-in one, so it also shows the
				// statuses that other extensions set with ctx.ui.setStatus().
				const statuses = [...footerData.getExtensionStatuses().entries()]
					.sort(([a], [b]) => a.localeCompare(b))
					.map(([, text]) => text.replace(/\s+/g, " ").trim());
				if (statuses.length > 0) lines.push(statuses.join(" "));

				return lines.map((text) => truncateToWidth(text, width, "…"));
			},
		}));
	});
}
