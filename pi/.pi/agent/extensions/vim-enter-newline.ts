/**
 * Vim Enter newline
 *
 * With pi-vim, Enter in insert mode adds a new line. Enter in normal mode
 * submits the prompt. When the autocomplete list shows, Enter selects the item.
 *
 * A keybinding cannot do this: Pi reads the same bindings in all modes, and
 * pi-vim sends the normal-mode Enter to the Pi editor.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

type ModalEditor = {
	focused?: boolean;
	getMode?: () => string;
	isShowingAutocomplete?: () => boolean;
};

const WRAPPED = Symbol("vim-enter-newline");

export default function (pi: ExtensionAPI) {
	let editor: ModalEditor | undefined;
	let unsubscribe: (() => void) | undefined;

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;

		unsubscribe?.();
		unsubscribe = ctx.ui.onTerminalInput((data) => {
			// "\n" is already the newline key, so do not touch it.
			if (data === "\n" || !matchesKey(data, "enter")) return undefined;
			if (!editor?.focused || editor.isShowingAutocomplete?.()) return undefined;
			if (editor.getMode?.() !== "insert") return undefined;
			return { data: "\n" };
		});

		// pi-vim sets its editor in its own session_start handler. Wait for it,
		// then wrap the factory to keep a reference to the editor.
		setTimeout(() => {
			const previous = ctx.ui.getEditorComponent();
			if (!previous || (previous as { [WRAPPED]?: boolean })[WRAPPED]) return;
			const factory: typeof previous = (tui, theme, keybindings) => {
				const instance = previous(tui, theme, keybindings);
				editor = instance as ModalEditor;
				return instance;
			};
			(factory as { [WRAPPED]?: boolean })[WRAPPED] = true;
			ctx.ui.setEditorComponent(factory);
		}, 0);
	});

	pi.on("session_shutdown", () => {
		unsubscribe?.();
		unsubscribe = undefined;
		editor = undefined;
	});
}
