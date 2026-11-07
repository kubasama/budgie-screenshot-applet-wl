/*
 * Popover UI. Mode icons are from Stefan Ric's budgie-screenshot-applet
 * (GPL-2.0-or-later).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class ScreenshotPopover : Budgie.Popover {
		private Settings settings;
		private Capture capture;
		private Gtk.Stack stack;
		private Gtk.Button window_button;
		private Gtk.Button screen_button;
		private Gtk.SpinButton delay_spin;
		private Gtk.ListBox history_list;
		private Gtk.Expander history_expander;
		private Gtk.Button clear_button;
		private Gtk.Label status_label;

		private Gtk.ListBox window_list;
		private Gtk.Spinner window_spinner;
		private Gtk.Label window_message;

		public signal void capture_requested(Mode mode, string? window_id);

		public ScreenshotPopover(Gtk.Widget relative_to, Settings settings, Capture capture) {
			Object(relative_to: relative_to);
			this.settings = settings;
			this.capture = capture;
			get_style_context().add_class("screenshot-wl-popover");

			stack = new Gtk.Stack();
			stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
			stack.vhomogeneous = false;
			stack.interpolate_size = true;
			stack.add_named(build_main_page(), "main");
			stack.add_named(build_window_page(), "windows");
			add(stack);

			settings.changed["history"].connect(rebuild_history);
			settings.changed["show-thumbnails"].connect(rebuild_history);
			settings.changed["editor-command"].connect(rebuild_history);
			capture.failed.connect((msg) => {
				status_label.label = msg;
				status_label.show();
			});
			capture.taken.connect(() => status_label.hide());

			rebuild_history();
			stack.show_all();

			map.connect(() => {
				Idle.add(() => {
					if (stack.visible_child_name == "main") screen_button.grab_focus();
					// GTK selects the spin button's text when the popover opens; clear it
					delay_spin.select_region(0, 0);
					return Source.REMOVE;
				});
			});
		}

		public void reset_page() {
			stack.set_visible_child_full("main", Gtk.StackTransitionType.NONE);
			screen_button.grab_focus();
		}

		/* ------------------------------------------------------------------ */
		/* main page                                                          */
		/* ------------------------------------------------------------------ */

		private Gtk.Widget build_main_page() {
			var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
			root.margin = 10;
			root.set_size_request(340, -1);

			/* one setting per row: label left, control right (like Budgie Screenshot) */
			var opts = new Gtk.Grid();
			opts.column_spacing = 12;
			opts.row_spacing = 8;
			opts.margin_start = 4;
			opts.margin_end = 4;

			var delay = new Gtk.SpinButton.with_range(0, 60, 1);
			delay_spin = delay;
			delay.width_chars = 2;
			delay.halign = Gtk.Align.END;
			delay.valign = Gtk.Align.CENTER;
			settings.bind("delay", delay, "value", SettingsBindFlags.DEFAULT);

			option_row(opts, 0, _("Delay in seconds"), delay);
			option_row(opts, 1, _("Show pointer"), bound_switch("include-pointer"));
			option_row(opts, 2, _("Save to disk"), bound_switch("save-to-disk"));
			root.pack_start(opts, false, false, 0);
			root.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL), false, false, 2);

			var modes = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			modes.homogeneous = true;
			screen_button = mode_button("screen", _("Screen"),
				() => capture_requested(Mode.MONITOR, null));
			modes.pack_start(screen_button);
			window_button = mode_button("window", _("Window"), () => {
				if (capture.window_supported) {
					show_window_page();
				} else {
					status_label.label = capture.window_unsupported_reason;
					status_label.show();
				}
			});
			modes.pack_start(window_button);
			modes.pack_start(mode_button("selection", _("Selection"),
				() => capture_requested(Mode.AREA, null)));
			root.pack_start(modes, false, false, 0);

			status_label = new Gtk.Label("");
			status_label.get_style_context().add_class("dim-label");
			status_label.wrap = true;
			status_label.max_width_chars = 40;
			status_label.no_show_all = true;
			root.pack_start(status_label, false, false, 0);

			/* history, collapsed by default */
			history_expander = new Gtk.Expander("<b>%s</b>".printf(_("Recent screenshots")));
			history_expander.use_markup = true;
			settings.bind("history-expanded", history_expander, "expanded", SettingsBindFlags.DEFAULT);
			settings.bind("show-history", history_expander, "visible", SettingsBindFlags.GET);
			history_expander.no_show_all = true; // visibility comes from the setting only

			var hist_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
			hist_box.margin_top = 6;

			history_list = new Gtk.ListBox();
			history_list.selection_mode = Gtk.SelectionMode.NONE;
			history_list.activate_on_single_click = true;
			var placeholder = new Gtk.Label(_("Your screenshots will show up here"));
			placeholder.get_style_context().add_class("dim-label");
			placeholder.margin = 18;
			placeholder.show();
			history_list.set_placeholder(placeholder);
			history_list.row_activated.connect((row) => {
				var path = row.get_data<string>("path");
				hide();
				Util.open_uri(path);
			});

			var scroll = new Gtk.ScrolledWindow(null, null);
			scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
			scroll.propagate_natural_height = true;
			scroll.max_content_height = 330;
			scroll.add(history_list);
			hist_box.pack_start(scroll, true, true, 0);

			clear_button = new Gtk.Button.with_label(_("Clear history"));
			clear_button.relief = Gtk.ReliefStyle.NONE;
			clear_button.clicked.connect(clear_history);

			var folder_btn = new Gtk.Button.with_label(_("Open folder"));
			folder_btn.relief = Gtk.ReliefStyle.NONE;
			folder_btn.clicked.connect(() => {
				hide();
				string dir = Util.save_dir(settings);
				DirUtils.create_with_parents(dir, 0755);
				Util.open_uri(dir);
			});

			var hist_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			hist_buttons.homogeneous = true;
			hist_buttons.pack_start(folder_btn, true, true, 0);
			hist_buttons.pack_start(clear_button, true, true, 0);
			hist_box.pack_start(hist_buttons, false, false, 0);

			history_expander.add(hist_box);
			hist_box.show_all();

			var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
			settings.bind("show-history", sep, "visible", SettingsBindFlags.GET);
			sep.no_show_all = true;
			root.pack_start(sep, false, false, 2);
			root.pack_start(history_expander, true, true, 0);

			return root;
		}

		private delegate void Clicked();

		private Gtk.Button mode_button(string icon, string label, owned Clicked cb) {
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			box.margin = 6;
			var img = new Gtk.Image();
			img.set_size_request(64, 64);
			load_icon(img, icon);
			img.realize.connect(() => load_icon(img, icon));
			img.notify["scale-factor"].connect(() => load_icon(img, icon));
			img.style_updated.connect(() => {
				if (settings.get_string("icon-style") == "budgie") load_icon(img, icon);
			});
			settings.changed["icon-style"].connect(() => load_icon(img, icon));
			box.pack_start(img, false, false, 0);
			box.pack_start(new Gtk.Label(label), false, false, 0);

			var btn = new Gtk.Button();
			btn.relief = Gtk.ReliefStyle.NONE;
			btn.add(box);
			btn.clicked.connect(() => cb());
			return btn;
		}

		private const string[] BUDGIE_ICONS = { "screen", "bsw-selectscreen-symbolic",
			"window", "bsw-selectwindow-symbolic", "selection", "bsw-selectselection-symbolic" };

		/* Classic: bundled PNGs from the old applet (64px + @2x).
		 * Budgie: Budgie Screenshot's symbolic SVGs, tinted with the theme colour. */
		private void load_icon(Gtk.Image img, string name) {
			if (settings.get_string("icon-style") == "budgie") {
				for (int i = 0; i < BUDGIE_ICONS.length; i += 2) {
					if (BUDGIE_ICONS[i] == name) {
						img.set_from_icon_name(BUDGIE_ICONS[i + 1], Gtk.IconSize.DIALOG);
						img.pixel_size = 48;
						return;
					}
				}
			}

			int sf = int.max(1, img.get_scale_factor());
			string path = "%s/icons/%s%s.png".printf(RESOURCE_PATH, name, sf >= 2 ? "@2x" : "");
			try {
				var pix = new Gdk.Pixbuf.from_resource(path);
				int target = 64 * sf;
				if (pix.width != target) pix = pix.scale_simple(target, target, Gdk.InterpType.BILINEAR);
				img.pixel_size = -1;
				img.set_from_surface(Gdk.cairo_surface_create_from_pixbuf(pix, sf, img.get_window()));
			} catch (Error e) {
				warning("Icon %s: %s", path, e.message);
			}
		}

		private void option_row(Gtk.Grid grid, int row, string text, Gtk.Widget control) {
			var l = new Gtk.Label(text);
			l.halign = Gtk.Align.START;
			l.hexpand = true;
			grid.attach(l, 0, row);
			grid.attach(control, 1, row);
		}

		private Gtk.Switch bound_switch(string key) {
			var sw = new Gtk.Switch();
			sw.valign = Gtk.Align.CENTER;
			sw.halign = Gtk.Align.END;
			settings.bind(key, sw, "active", SettingsBindFlags.DEFAULT);
			return sw;
		}

		private void clear_history() {
			foreach (var p in settings.get_strv("history")) {
				if (Util.is_unsaved(p)) FileUtils.unlink(p);
			}
			settings.set_strv("history", {});
		}

		/* ------------------------------------------------------------------ */
		/* window picker page                                                 */
		/* ------------------------------------------------------------------ */

		private Gtk.Widget build_window_page() {
			var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
			root.margin = 10;
			root.set_size_request(340, -1);

			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			var back = new Gtk.Button.from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON);
			back.relief = Gtk.ReliefStyle.NONE;
			back.clicked.connect(() => stack.visible_child_name = "main");
			header.pack_start(back, false, false, 0);
			var title = new Gtk.Label("<b>%s</b>".printf(_("Pick a window")));
			title.use_markup = true;
			header.pack_start(title, true, true, 0);
			window_spinner = new Gtk.Spinner();
			header.pack_end(window_spinner, false, false, 0);
			root.pack_start(header, false, false, 0);

			window_message = new Gtk.Label("");
			window_message.get_style_context().add_class("dim-label");
			window_message.wrap = true;
			window_message.max_width_chars = 40;
			window_message.no_show_all = true;
			root.pack_start(window_message, false, false, 0);

			window_list = new Gtk.ListBox();
			window_list.selection_mode = Gtk.SelectionMode.NONE;
			window_list.activate_on_single_click = true;
			window_list.row_activated.connect((row) => {
				capture_requested(Mode.WINDOW, row.get_data<string>("id"));
			});

			var scroll = new Gtk.ScrolledWindow(null, null);
			scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
			scroll.propagate_natural_height = true;
			scroll.max_content_height = 380;
			scroll.add(window_list);
			root.pack_start(scroll, true, true, 0);
			return root;
		}

		private void show_window_page() {
			stack.visible_child_name = "windows";
			foreach (var c in window_list.get_children()) c.destroy();
			window_message.hide();
			window_spinner.start();

			WindowList.fetch.begin((obj, res) => {
				window_spinner.stop();
				try {
					var wins = WindowList.fetch.end(res);
					if (wins.length() == 0) {
						window_message.label = _("No windows open");
						window_message.show();
					}
					foreach (var w in wins) window_list.add(window_row(w));
					window_list.show_all();
				} catch (Error e) {
					window_message.label = e.message;
					window_message.show();
				}
			});
		}

		private Gtk.ListBoxRow window_row(WindowInfo w) {
			var row = new Gtk.ListBoxRow();
			row.set_data<string>("id", w.id);
			var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
			box.margin = 6;
			var icon = new Gtk.Image.from_gicon(w.icon(), Gtk.IconSize.LARGE_TOOLBAR);
			icon.pixel_size = 24;
			box.pack_start(icon, false, false, 0);
			var label = new Gtk.Label(w.display_title());
			label.halign = Gtk.Align.START;
			label.ellipsize = Pango.EllipsizeMode.END;
			label.max_width_chars = 34;
			box.pack_start(label, true, true, 0);
			row.add(box);
			return row;
		}

		/* ------------------------------------------------------------------ */
		/* history                                                            */
		/* ------------------------------------------------------------------ */

		private void rebuild_history() {
			foreach (var child in history_list.get_children()) {
				child.destroy();
			}

			int n = 0;
			foreach (var path in settings.get_strv("history")) {
				if (!FileUtils.test(path, FileTest.EXISTS)) continue;
				history_list.add(history_row(path));
				n++;
			}
			clear_button.sensitive = n > 0;
			history_expander.label = n > 0
				? "<b>%s</b>  <small>(%d)</small>".printf(_("Recent screenshots"), n)
				: "<b>%s</b>".printf(_("Recent screenshots"));
			history_list.show_all();
		}

		private Gtk.ListBoxRow history_row(string path) {
			bool unsaved = Util.is_unsaved(path);
			var row = new Gtk.ListBoxRow();
			row.set_data<string>("path", path);

			var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			box.margin = 4;

			if (settings.get_boolean("show-thumbnails")) {
				var thumb = new Gtk.Image.from_icon_name("image-x-generic-symbolic", Gtk.IconSize.DND);
				thumb.set_size_request(96, 54);
				load_thumbnail.begin(path, thumb);
				box.pack_start(thumb, false, false, 0);
			}

			var text = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
			text.valign = Gtk.Align.CENTER;
			var name = new Gtk.Label(unsaved ? _("Clipboard only") : Path.get_basename(path));
			name.halign = Gtk.Align.START;
			name.ellipsize = unsaved ? Pango.EllipsizeMode.END : Pango.EllipsizeMode.MIDDLE;
			name.max_width_chars = 20;
			if (unsaved) name.get_style_context().add_class("dim-label");
			text.pack_start(name, false, false, 0);

			var when = new Gtk.Label(describe_time(path));
			when.halign = Gtk.Align.START;
			when.get_style_context().add_class("dim-label");
			text.pack_start(when, false, false, 0);
			box.pack_start(text, true, true, 0);

			var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			actions.valign = Gtk.Align.CENTER;
			actions.pack_start(icon_button("edit-copy-symbolic", "Copy image to clipboard", () => {
				Util.copy_to_clipboard.begin(path, (o, r) => {
					try {
						Util.copy_to_clipboard.end(r);
					} catch (Error e) {
						status_label.label = e.message;
						status_label.show();
					}
				});
			}), false, false, 0);

			if (Util.editor_argv(settings, path) != null) {
				actions.pack_start(icon_button("document-edit-symbolic", "Annotate / edit", () => {
					hide();
					Util.spawn(Util.editor_argv(settings, path));
				}), false, false, 0);
			}

			if (unsaved) {
				actions.pack_start(icon_button("document-save-symbolic", "Save to the screenshots folder", () => {
					try {
						Util.save_permanently(settings, path);
					} catch (Error e) {
						status_label.label = e.message;
						status_label.show();
					}
				}), false, false, 0);
			} else {
				actions.pack_start(icon_button("folder-open-symbolic", "Show in folder", () => {
					hide();
					Util.show_in_folder(path);
				}), false, false, 0);
			}

			actions.pack_start(icon_button("user-trash-symbolic", unsaved ? "Delete" : "Move to trash", () => {
				try {
					if (unsaved) {
						FileUtils.unlink(path);
					} else {
						File.new_for_path(path).trash();
					}
				} catch (Error e) {
					warning("Delete failed: %s", e.message);
				}
				string[] left = {};
				foreach (var p in settings.get_strv("history")) {
					if (p != path) left += p;
				}
				settings.set_strv("history", left);
			}), false, false, 0);

			box.pack_end(actions, false, false, 0);
			row.add(box);
			return row;
		}

		private Gtk.Button icon_button(string icon, string tip, owned Clicked cb) {
			var b = new Gtk.Button.from_icon_name(icon, Gtk.IconSize.BUTTON);
			b.relief = Gtk.ReliefStyle.NONE;
			b.valign = Gtk.Align.CENTER;
			b.clicked.connect(() => cb());
			return b;
		}

		private async void load_thumbnail(string path, Gtk.Image target) {
			try {
				var stream = yield File.new_for_path(path).read_async();
				var pix = yield new Gdk.Pixbuf.from_stream_at_scale_async(stream, 96, 54, true, null);
				target.set_from_pixbuf(pix);
			} catch (Error e) {
				// keep the generic icon
			}
		}

		private string describe_time(string path) {
			try {
				var info = File.new_for_path(path).query_info(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
				var dt = info.get_modification_date_time();
				if (dt == null) return "";
				dt = dt.to_local();
				var now = new DateTime.now_local();
				if (dt.get_year() == now.get_year() && dt.get_day_of_year() == now.get_day_of_year()) {
					/* TRANSLATORS: strftime format, keep the % codes */
					return dt.format(_("Today %H:%M:%S"));
				}
				/* TRANSLATORS: strftime format, keep the % codes */
				return dt.format(_("%Y-%m-%d %H:%M"));
			} catch (Error e) {
				return "";
			}
		}
	}
}
