# Changelog

## 0.1.0 (minimalist fork) - [2026-05-09]

This is a personal minimalist fork of `bwya77/vscode-dark-islands`. The goal is to keep the floating glass islands aesthetic but pair it with a slimmer top bar and a less black palette that fits with One Dark Pro Mix (or any other custom theme the user already has).

### CHANGED
- `settings.json` no longer forces `workbench.colorTheme: "Islands Dark"`. The CSS variables drive the look, so users can keep their own theme (e.g. One Dark Pro Mix) and the panels/activity bar/status bar will adopt the canvas/surface colors below.
- Canvas/surface tuned to dark gray instead of near-black: `--islands-bg-canvas: #1c1f25`, `--islands-bg-surface: #282c34`. Pairs better with One Dark Pro Mix and similar themes.
- Workbench surface colors are now pinned through `workbench.colorCustomizations`, using the actual One Dark Pro Mix split: sidebar/activity/title/status `#21252b`, editor/terminal `#282c34`.
- `workbench.tree.indent` reduced from 16 to 6 to match the more compact look of the screenshot.

### ADDED
- `window.commandCenter: false` baked into the recommended settings (no pill-shaped command center, just the centered "Visual Studio Code" title).
- `workbench.layoutControl.enabled: false`, `workbench.editor.empty.hint: "hidden"`, `workbench.startupEditor: "none"` for a cleaner first-launch experience.
- Slim title bar (30px) with a faded "Visual Studio Code" label that brightens on hover.
- Subtle scrollbar thumb styling that preserves VS Code's default show/hide behavior instead of forcing scrollbars to stay visible.
- `install-minimalist.sh`: interactive p10k-style installer. Each step lives on its own cleared screen with a step counter, description, and a single yes/no question. A summary screen at the end lets the user review every choice before any change is applied.
- Activity-bar position step in the installer: `default` (vertical pill on left), `top` (horizontal pill above sidebar), `bottom` (horizontal pill below sidebar), or `hidden`. Each variant rewrites the activity-bar/composite-bar CSS rules in the user's stylesheet to a position-specific design.
- Icon-glow toggle in the installer (default off). Removes the `.monaco-icon-label.file-icon::before` rule when disabled.

### CHANGED
- `workbench.activityBar.location` is no longer baked into the repo's `settings.json`. The interactive installer asks for the user's preferred position and writes both the setting and the matching CSS variant, so re-running the script with a different choice fully switches the layout.

### NOTES
- Custom UI Style caches the CSS at injection time, so any change to `settings.json` (CSS merge, glow toggle, activity-bar variant) only becomes visible after running `Custom UI Style: Reload` (or the disable / enable cycle for stubborn cases). The installer's "Done" screen prints this prominently.

### FIXED
- `top`/`bottom` activity-bar layouts now style VS Code's header/footer composite bar instead of the hidden `.part.activitybar`, so the glass pill renders in all supported positions.
- The `top`/`bottom` activity bar pill is left-aligned with the sidebar content instead of being centered inside the panel.
- Removed canvas backgrounds from sidebar internals in non-default layouts to avoid the darker rectangle below the Explorer file list.
- Isolated panel border animations from the title bar so opened files no longer visually cover the top bar.
- Scrollbar thumbs no longer override VS Code's hidden state, so panes do not show scrollbars until VS Code actually needs to show them.
- Editor scrollbars use native editor settings plus an editor-scoped Monaco override, keeping the editor scrollbar visible without making sidebar/panel scrollbars appear everywhere.

---

## 0.0.2 - [2026-02-19]

### FIXED
- Fixed chat window colors broken: #15
- Install script (tested on MacOS) #5, #6
- The explorer pane would not show all items, some items would be cut off #67, #74, #66, #20, #12
- Commit message box cut off #57, #70
- Primary sidebar would be truncated if we moved it to the right #55
- Issue with explorer pane items being unselected but the file would remain selected. 
- Border radius of terminal does not match editor, chat, etc. #61
- Made the primary sidebar icons slightly larger (18px to 22px)
- Window controls background color is incorrect #72
- When opening VSCode with no open files, the default tab would be cut off. #30
- When working with `ipynb` files the editor wouldnt follow correct rendering and code blocks did not stand out #45
- Elements in the terminal when split screen would spill over
- Editor tabs overlapping with floating header in Linux #26
- Markdown files respect `font-family` CSS rules and render monospace fonts correctly #48

### ADDED
- Chat text window has rounded corners instead of squared #47
- Uninstall script (tested on MacOS)
- Funding.yml file 
- Users can set the 'roundness' of elements by modifying `css` variables. Please see the "Customizing Border Radius" section in the README.md file
- Users can set the spacing between elements such as the explorer pane, chat pane, editor, and temrinal. #17
- Users can now set the primary and secondary colors by setting the `islands-bg-surface` and `islands-bg-canvas` variables.
- 2px spacing between the terminal and editor. 
- The system dialog box now follows our theme with rounded corners
- Shadow under the sticky widget in the editor. 

### CHANGED
- Theme and settings.json file are versioned properly #17

### REMOVED
- Removed the highlight boxes in selection windows - these cannot be rounded #10
