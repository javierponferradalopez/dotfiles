/**
 * Vim mode
 *
 * Adds a normal mode to the Pi editor. Each normal-mode key sends the key that
 * the default editor already binds to the same action, so undo, the kill ring
 * and word motions stay those of Pi.
 *
 * - Escape: insert -> normal. In normal mode, Escape goes to Pi (abort, tree).
 * - Motions: h j k l, 0 ^ $, w e b
 * - Insert: i a I A o O
 * - Edit: x X D C S p u, dd dw db d0 d$, cc cw cb c0 c$
 * - Enter: insert mode adds a new line, normal mode submits. When the
 *   autocomplete list shows, Enter selects the item in both modes.
 * - Control keys work in both modes.
 */

import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const LEFT = "\x1b[D";
const DOWN = "\x1b[B";
const UP = "\x1b[A";
const RIGHT = "\x1b[C";
const LINE_START = "\x01"; // ctrl+a
const LINE_END = "\x05"; // ctrl+e
const WORD_LEFT = "\x1bb"; // alt+b
const WORD_RIGHT = "\x1bf"; // alt+f
const DELETE_CHAR = "\x1b[3~"; // delete
const BACKSPACE = "\x7f";
const DELETE_WORD_FORWARD = "\x1bd"; // alt+d
const DELETE_WORD_BACKWARD = "\x17"; // ctrl+w
const DELETE_TO_LINE_START = "\x15"; // ctrl+u
const DELETE_TO_LINE_END = "\x0b"; // ctrl+k
const YANK = "\x19"; // ctrl+y
const UNDO = "\x1f"; // ctrl+-
const NEW_LINE = "\n"; // ctrl+j

type Mode = "normal" | "insert";

interface Command {
	keys: string[];
	then?: Mode;
}

const MOTIONS: Record<string, string[]> = {
	h: [LEFT],
	j: [DOWN],
	k: [UP],
	l: [RIGHT],
	"0": [LINE_START],
	"^": [LINE_START],
	b: [WORD_LEFT],
};

const COMMANDS: Record<string, Command> = {
	i: { keys: [], then: "insert" },
	a: { keys: [RIGHT], then: "insert" },
	I: { keys: [LINE_START], then: "insert" },
	A: { keys: [LINE_END], then: "insert" },
	o: { keys: [LINE_END, NEW_LINE], then: "insert" },
	O: { keys: [LINE_START, NEW_LINE, UP], then: "insert" },
	X: { keys: [BACKSPACE] },
	D: { keys: [DELETE_TO_LINE_END] },
	C: { keys: [DELETE_TO_LINE_END], then: "insert" },
	S: { keys: [LINE_START, DELETE_TO_LINE_END], then: "insert" },
	p: { keys: [YANK] },
	u: { keys: [UNDO] },
};

// Keys after an operator (d or c). The operator key again means the full line.
const OPERATOR_TARGETS: Record<string, string[]> = {
	w: [DELETE_WORD_FORWARD],
	e: [DELETE_WORD_FORWARD],
	b: [DELETE_WORD_BACKWARD],
	"0": [DELETE_TO_LINE_START],
	"^": [DELETE_TO_LINE_START],
	$: [DELETE_TO_LINE_END],
};
const FULL_LINE = [LINE_START, DELETE_TO_LINE_END];

class VimEditor extends CustomEditor {
	private mode: Mode = "insert";
	private operator: "d" | "c" | undefined;

	handleInput(data: string): void {
		if (matchesKey(data, "escape")) {
			if (this.mode === "insert") {
				this.mode = "normal";
				this.stepOffLineEnd();
			} else if (this.operator) {
				this.operator = undefined;
			} else {
				super.handleInput(data);
			}
			return;
		}

		if (this.mode === "insert") {
			if (matchesKey(data, "enter") && !this.isShowingAutocomplete()) {
				this.send([NEW_LINE]);
				return;
			}
			super.handleInput(data);
			return;
		}

		if (this.operator) {
			const operator = this.operator;
			this.operator = undefined;
			const keys = data === operator ? FULL_LINE : OPERATOR_TARGETS[data];
			if (!keys) return;
			this.send(keys);
			if (operator === "c") this.mode = "insert";
			else if (data === "d") this.removeEmptyLine();
			else if (data === "w") this.deleteSpacesAfterCursor();
			return;
		}

		if (data === "d" || data === "c") {
			this.operator = data;
			return;
		}

		if (data === "$") {
			this.send([LINE_END]);
			this.stepOffLineEnd();
			return;
		}

		// Pi moves by word to the end of the word. Vim "w" goes to the start of
		// the next word, and "e" to the last character of the word.
		if (data === "w") {
			this.send([WORD_RIGHT]);
			this.skipSpaces();
			return;
		}

		if (data === "e") {
			this.send([RIGHT, WORD_RIGHT, LEFT]);
			return;
		}

		if (data === "x") {
			this.send([DELETE_CHAR]);
			this.stepOffLineEnd();
			return;
		}

		const motion = MOTIONS[data];
		if (motion) {
			this.send(motion);
			return;
		}

		const command = COMMANDS[data];
		if (command) {
			this.send(command.keys);
			if (command.then) this.mode = command.then;
			return;
		}

		// Normal mode ignores other printable keys. Control keys go to Pi.
		if (data.length === 1 && data.charCodeAt(0) >= 32) return;
		super.handleInput(data);
	}

	render(width: number): string[] {
		const lines = super.render(width);
		if (lines.length === 0) return lines;

		const label = this.mode === "normal" ? " NORMAL " : " INSERT ";
		const last = lines.length - 1;
		if (visibleWidth(lines[last]!) >= label.length) {
			lines[last] = truncateToWidth(lines[last]!, width - label.length, "") + label;
		}
		return lines;
	}

	private send(keys: string[]): void {
		for (const key of keys) super.handleInput(key);
	}

	// In normal mode the cursor stays on a character, as in Vim.
	private stepOffLineEnd(): void {
		const { line, col } = this.getCursor();
		const length = this.getLines()[line]?.length ?? 0;
		if (col > 0 && col >= length) this.send([LEFT]);
	}

	private isSpaceAtCursor(): boolean {
		const { line, col } = this.getCursor();
		const char = this.getLines()[line]?.[col];
		return char === " " || char === "\t";
	}

	private skipSpaces(): void {
		while (this.isSpaceAtCursor()) this.send([RIGHT]);
	}

	// Vim "dd" removes the line, not only its text.
	private removeEmptyLine(): void {
		const { line } = this.getCursor();
		const count = this.getLines().length;
		if (line < count - 1) this.send([DELETE_CHAR]);
		else if (line > 0) this.send([BACKSPACE]);
	}

	// Vim "dw" also deletes the spaces after the word.
	private deleteSpacesAfterCursor(): void {
		while (this.isSpaceAtCursor()) this.send([DELETE_CHAR]);
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent((tui, theme, keybindings) => new VimEditor(tui, theme, keybindings));
	});
}
