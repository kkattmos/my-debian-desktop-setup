import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';
import {EndSessionDialog} from 'resource:///org/gnome/shell/ui/endSessionDialog.js';

const FIREFOX = 'firefox-esr.desktop';
const CLAUDE = 'com.anthropic.Claude.desktop';
const CLAUDE_NEW_CHAT = 'claude://claude.ai/new?surface=chat&source=desktop_action';
// OneTab's "Send all tabs in all windows to OneTab" has no default key: set it to this one in Firefox
// (about:addons > gear > Manage Extension Shortcuts). F12 exists in every layout, letters don't in Thai.
const ONETAB_KEYS = [Clutter.KEY_Shift_L, Clutter.KEY_Alt_L, Clutter.KEY_F12];

const sleep = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));

async function waitFor(test, ms) {
    for (let t = 0; t < ms && !test(); t += 100)
        await sleep(100);
    return test();
}

const app = id => Shell.AppSystem.get_default().lookup_app(id);
const normalWindows = a => a?.get_windows().filter(w => w.get_window_type() === Meta.WindowType.NORMAL) ?? [];

function bringClaude() {
    const win = normalWindows(app(CLAUDE))[0];
    if (win) {
        if (!win.is_on_all_workspaces())
            win.change_workspace(global.workspace_manager.get_active_workspace());
        win.activate(global.get_current_time());
    }
    // Single-instance app: a second launch hands the URL to the running one (or starts it here).
    Util.spawn(['claude-desktop', CLAUDE_NEW_CHAT]);
}

export default class TidySessionExtension extends Extension {
    enable() {
        // Same mechanism as GNOME's own custom shortcuts, so no gsettings schema is needed.
        this._actions = new Map();
        for (const [accel, run] of [
            ['<Super>b', () => Util.spawn(['firefox-esr', '--new-window'])],
            ['<Super>c', bringClaude],
        ]) {
            const action = global.display.grab_accelerator(accel, Meta.KeyBindingFlags.NONE);
            if (action === Meta.KeyBindingAction.NONE) {
                console.warn(`tidy-session: ${accel} is taken`);
                continue;
            }
            Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action),
                Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW);
            this._actions.set(action, run);
        }
        this._accelId = global.display.connect('accelerator-activated',
            (_display, action) => this._actions.get(action)?.());

        // Every confirm path (Power Off, Restart, Log Out buttons and the 60 s countdown) ends in _confirm.
        const orig = EndSessionDialog.prototype._confirm;
        this._origConfirm = orig;
        const tidy = () => this._tidy();
        EndSessionDialog.prototype._confirm = async function (signal) {
            // The countdown confirms with the dialog still open; its modal grab would eat the OneTab keys.
            this.close(true);
            try {
                await tidy();
            } catch (e) {
                console.error(e);
            }
            return orig.call(this, signal);
        };
    }

    disable() {
        EndSessionDialog.prototype._confirm = this._origConfirm;
        global.display.disconnect(this._accelId);
        for (const action of this._actions.keys()) {
            global.display.ungrab_accelerator(action);
            Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NONE);
        }
        this._actions = null;
        this._keyboard?.run_dispose();
        this._keyboard = null;
    }

    _press(keyvals) {
        this._keyboard ??= Clutter.get_default_backend().get_default_seat()
            .create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        for (const k of keyvals)
            this._keyboard.notify_keyval(GLib.get_monotonic_time(), k, Clutter.KeyState.PRESSED);
        for (const k of [...keyvals].reverse())
            this._keyboard.notify_keyval(GLib.get_monotonic_time(), k, Clutter.KeyState.RELEASED);
    }

    async _tidy() {
        const firefox = app(FIREFOX);
        const windows = () => normalWindows(firefox);
        const win = windows()[0];
        if (win) {
            win.activate(global.get_current_time());
            if (await waitFor(() => global.display.focus_window === win, 2000))
                this._press(ONETAB_KEYS);
            // OneTab closes every tab it saved and leaves one window showing its own page.
            if (await waitFor(() => windows().length === 1 && windows()[0].get_title()?.startsWith('OneTab'), 5000)) {
                firefox.request_quit();
                await waitFor(() => firefox.state === Shell.AppState.STOPPED, 10000);
            } else {
                // Leave Firefox running: being killed at session end keeps its crash restore of the tabs.
                console.warn('tidy-session: OneTab did not take the tabs (shortcut not set? pinned tabs?)');
            }
        }

        const claude = app(CLAUDE);
        if (claude && claude.state !== Shell.AppState.STOPPED) {
            claude.request_quit();
            await waitFor(() => claude.state === Shell.AppState.STOPPED, 10000);
        }
    }
}
