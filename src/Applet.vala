/*
 * Screenshot applet for Budgie 10.10+ (Wayland).
 * Successor of Stefan Ric's budgie-screenshot-applet.
 *
 *  Left click   : open the popover (Screen / Window / Selection + history)
 *  Middle click : capture a selection straight away
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
		public Budgie.Applet get_panel_widget(string uuid) {
			return new Applet(uuid);
		}
	}

	public class Applet : Budgie.Applet {
		public string uuid { public set; public get; }

		private Gtk.EventBox event_box;
		private ScreenshotPopover popover;
		private unowned Budgie.PopoverManager? manager = null;
		private Settings settings;
		private Capture capture;

		public Applet(string uuid) {
			Object(uuid: uuid);

			settings = new Settings(SCHEMA_ID);
			// Budgie Screenshot style icons (bsw-*-symbolic)
			Gtk.IconTheme.get_default().add_resource_path(RESOURCE_PATH + "/icons/symbolic");
			capture = new Capture(settings);

			event_box = new Gtk.EventBox();
			event_box.add(new Indicator(settings, capture));
			event_box.tooltip_text = _("Screenshot");
			add(event_box);

			popover = new ScreenshotPopover(event_box, settings, capture);
			popover.capture_requested.connect(start_capture);

			capture.taken.connect(() => {
				if (settings.get_boolean("reopen-popover")) {
					// wait for the panel face animation to start before popping up
					Timeout.add(400, () => {
						show_popover();
						return Source.REMOVE;
					});
				}
			});

			event_box.button_press_event.connect((e) => {
				switch (e.button) {
					case 1:
						if (popover.get_visible()) {
							popover.hide();
						} else if (!capture.busy) {
							show_popover();
						}
						return Gdk.EVENT_STOP;
					case 2:
						start_capture(Mode.AREA, null);
						return Gdk.EVENT_STOP;
					default:
						return Gdk.EVENT_PROPAGATE;
				}
			});

			show_all();
		}

		private void show_popover() {
			if (manager == null) return;
			popover.reset_page();
			popover.show_all();
			manager.show_popover(event_box);
		}

		private void start_capture(Mode mode, string? window_id) {
			if (capture.busy) return;
			popover.hide();
			capture.run.begin(mode, window_id);
		}

		public override void update_popovers(Budgie.PopoverManager? manager) {
			manager.register_popover(event_box, popover);
			this.manager = manager;
		}

		public override bool supports_settings() {
			return true;
		}

		public override Gtk.Widget? get_settings_ui() {
			return new SettingsView(settings);
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	Intl.bindtextdomain(ScreenshotWl.Config.GETTEXT_PACKAGE, ScreenshotWl.Config.LOCALEDIR);
	Intl.bind_textdomain_codeset(ScreenshotWl.Config.GETTEXT_PACKAGE, "UTF-8");

	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(ScreenshotWl.Plugin));
}
