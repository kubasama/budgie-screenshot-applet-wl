/*
 * Shown in Budgie Desktop Settings -> Panel -> applet settings
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class SettingsView : Gtk.Grid {
		private Settings settings;
		private int row = 0;

		public SettingsView(Settings settings) {
			this.settings = settings;
			row_spacing = 8;
			column_spacing = 12;
			margin = 6;

			var folder = new Gtk.FileChooserButton(_("Screenshot folder"), Gtk.FileChooserAction.SELECT_FOLDER);
			folder.set_filename(Util.save_dir(settings));
			folder.file_set.connect(() => {
				var f = folder.get_filename();
				if (f != null) settings.set_string("save-path", f);
			});
			add_row(_("Save to"), folder);

			add_switch(_("Save screenshots to disk"), "save-to-disk", null);
			var copy = add_switch(_("Copy to clipboard"), "copy-to-clipboard", Util.have("wl-copy") ? null : _("wl-copy not found"));
			// when not saving, copying is the whole point, so it's always on
			settings.bind("save-to-disk", copy, "sensitive", SettingsBindFlags.GET);
			var style = new Gtk.ComboBoxText();
			style.append("classic", _("Budgie Classic"));
			style.append("budgie", _("Budgie Screenshot"));
			settings.bind("icon-style", style, "active-id", SettingsBindFlags.DEFAULT);
			add_row(_("Button icons"), style);

			add_switch(_("Flash the screen on capture"), "flash", null);
			add_switch(_("Show notification"), "show-notification", null);
			add_switch(_("Show a face in the panel after a capture"), "show-emoji", null);
			add_switch(_("Show recent screenshots in the popover"), "show-history", null);
			add_switch(_("Shutter sound"), "play-sound", Util.have("canberra-gtk-play") ? null : _("canberra-gtk-play not found"));
			add_switch(_("Re-open applet after capture"), "reopen-popover", null);
			add_switch(_("Show thumbnails"), "show-thumbnails", null);

			var size = new Gtk.SpinButton.with_range(0, 50, 1);
			settings.bind("history-size", size, "value", SettingsBindFlags.DEFAULT);
			add_row(_("History size"), size);

			var fmt = new Gtk.Entry();
			fmt.tooltip_text = _("strftime format, e.g. %Y-%m-%d_%H%M%S");
			settings.bind("filename-format", fmt, "text", SettingsBindFlags.DEFAULT);
			add_row(_("File name"), fmt);

			var editor = new Gtk.Entry();
			editor.placeholder_text = _("auto (satty / swappy)");
			editor.tooltip_text = _("Command used by the Edit button; the file path is appended");
			settings.bind("editor-command", editor, "text", SettingsBindFlags.DEFAULT);
			add_row(_("Editor"), editor);

			show_all();
		}

		private void add_row(string label, Gtk.Widget w) {
			var l = new Gtk.Label(label);
			l.halign = Gtk.Align.START;
			l.hexpand = true;
			w.halign = Gtk.Align.END;
			attach(l, 0, row);
			attach(w, 1, row);
			row++;
		}

		private Gtk.Switch add_switch(string label, string key, string? warning_text) {
			var sw = new Gtk.Switch();
			sw.valign = Gtk.Align.CENTER;
			settings.bind(key, sw, "active", SettingsBindFlags.DEFAULT);
			string text = label;
			if (warning_text != null) {
				sw.tooltip_text = warning_text;
				text = "%s (%s)".printf(label, warning_text);
			}
			add_row(text, sw);
			return sw;
		}
	}
}
