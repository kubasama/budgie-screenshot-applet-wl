/*
 * Panel icon: camera normally, countdown during the delay and a random
 * face when the shot is taken (like the old applet did).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class Indicator : Gtk.Stack {
		private const string[] FACES = {
			"face-angel-symbolic", "face-cool-symbolic", "face-devilish-symbolic",
			"face-kiss-symbolic", "face-laugh-symbolic", "face-monkey-symbolic",
			"face-raspberry-symbolic", "face-smile-symbolic", "face-smile-big-symbolic",
			"face-smirk-symbolic", "face-surprise-symbolic", "face-wink-symbolic"
		};

		private Gtk.Image face;
		private Gtk.Label count;
		private uint reset_id = 0;
		private Settings settings;

		public Indicator(Settings settings, Capture capture) {
			this.settings = settings;
			transition_type = Gtk.StackTransitionType.SLIDE_DOWN;
			transition_duration = 200;

			var camera = new Gtk.Image.from_gicon(
				new ThemedIcon.from_names({ "camera-photo-symbolic", "camera-web-symbolic", "applets-screenshooter-symbolic" }),
				Gtk.IconSize.MENU);
			face = new Gtk.Image();
			count = new Gtk.Label("");
			count.use_markup = true;

			add_named(camera, "normal");
			add_named(count, "count");
			add_named(face, "face");
			visible_child_name = "normal";

			capture.tick.connect((left) => {
				cancel_reset();
				count.set_markup("<b>%d</b>".printf(left));
				visible_child_name = "count";
			});
			capture.taken.connect(() => {
				if (!settings.get_boolean("show-emoji")) {
					visible_child_name = "normal";
					return;
				}
				face.set_from_icon_name(FACES[Random.int_range(0, FACES.length)], Gtk.IconSize.MENU);
				visible_child_name = "face";
				cancel_reset();
				reset_id = Timeout.add(1500, () => {
					reset_id = 0;
					visible_child_name = "normal";
					return Source.REMOVE;
				});
			});
			capture.finished.connect(() => {
				if (reset_id == 0) visible_child_name = "normal";
			});

			show_all();
		}

		private void cancel_reset() {
			if (reset_id != 0) {
				Source.remove(reset_id);
				reset_id = 0;
			}
		}
	}
}
