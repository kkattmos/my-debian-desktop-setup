import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

// GNOME stores workspace names here (same key GNOME Tweaks / Workspace Indicator use).
const WM_SCHEMA = 'org.gnome.desktop.wm.preferences';
const NAMES_KEY = 'workspace-names';

const WorkspaceLabel = GObject.registerClass(
class WorkspaceLabel extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Workspace Label');

        this._settings = new Gio.Settings({schema_id: WM_SCHEMA});
        this._label = new St.Label({
            text: '',
            style_class: 'workspace-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._label);

        const wm = global.workspace_manager;
        this._handlers = [
            [wm, wm.connect('active-workspace-changed', () => this._sync())],
            [wm, wm.connect('notify::n-workspaces', () => this._sync())],
            [this._settings, this._settings.connect(`changed::${NAMES_KEY}`, () => this._sync())],
        ];

        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._buildMenu();
        });

        this._sync();
    }

    _names() {
        return this._settings.get_strv(NAMES_KEY);
    }

    _nameFor(index, names = this._names()) {
        return names[index]?.trim() || `Workspace ${index + 1}`;
    }

    _sync() {
        const active = global.workspace_manager.get_active_workspace_index();
        this._label.text = this._nameFor(active);
    }

    _buildMenu() {
        this.menu.removeAll();

        const wm = global.workspace_manager;
        const active = wm.get_active_workspace_index();
        const names = this._names();

        for (let i = 0; i < wm.n_workspaces; i++) {
            const item = new PopupMenu.PopupMenuItem(`${i + 1}. ${this._nameFor(i, names)}`);
            item.setOrnament(i === active ? PopupMenu.Ornament.DOT : PopupMenu.Ornament.NONE);
            item.connect('activate', () => {
                wm.get_workspace_by_index(i)?.activate(global.get_current_time());
            });
            this.menu.addMenuItem(item);
        }

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const entryItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const entry = new St.Entry({
            style_class: 'workspace-label-entry',
            hint_text: 'Rename this workspace, then Enter',
            text: names[active] ?? '',
            can_focus: true,
            x_expand: true,
        });
        entry.clutter_text.connect('activate', () => {
            this._rename(active, entry.text);
            this.menu.close();
        });
        entryItem.add_child(entry);
        this.menu.addMenuItem(entryItem);
    }

    _rename(index, text) {
        const names = this._names();
        while (names.length <= index)
            names.push('');
        names[index] = text.trim();
        // Drop trailing blanks so unnamed workspaces fall back to "Workspace N".
        while (names.length && !names[names.length - 1])
            names.pop();
        this._settings.set_strv(NAMES_KEY, names);
    }

    destroy() {
        for (const [obj, id] of this._handlers)
            obj.disconnect(id);
        this._handlers = [];
        this._settings = null;
        super.destroy();
    }
});

export default class WorkspaceLabelExtension extends Extension {
    enable() {
        this._indicator = new WorkspaceLabel();
        // Index 1 in the left box = right after the Activities button.
        Main.panel.addToStatusArea(this.uuid, this._indicator, 1, 'left');
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
