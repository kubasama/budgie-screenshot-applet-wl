/*
 * Optional white flash over every monitor after a capture.
 * Uses a click-through layer-shell overlay, so it never steals focus.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class Flash : Object {
		private const double START_ALPHA = 0.7;
		private const int DURATION_MS = 300;

		public static void show() {
			var display = Gdk.Display.get_default();
			if (display == null || !GtkLayerShell.is_supported()) return;
			for (int i = 0; i < display.get_n_monitors(); i++) {
				flash_monitor(display.get_monitor(i));
			}
		}

		private static void flash_monitor(Gdk.Monitor monitor) {
			var win = new Gtk.Window(Gtk.WindowType.TOPLEVEL);
			GtkLayerShell.init_for_window(win);
			GtkLayerShell.set_namespace(win, "screenshot-flash");
			GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY);
			GtkLayerShell.set_monitor(win, monitor);
			GtkLayerShell.set_exclusive_zone(win, -1);
			GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE);
			GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, true);
			GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, true);
			GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, true);
			GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, true);

			var visual = win.get_screen().get_rgba_visual();
			if (visual != null) win.set_visual(visual);
			win.app_paintable = true;

			double alpha = START_ALPHA;
			win.draw.connect((cr) => {
				cr.set_operator(Cairo.Operator.SOURCE);
				cr.set_source_rgba(1, 1, 1, alpha);
				cr.paint();
				return true;
			});
			// clicks go straight through
			win.realize.connect(() => win.input_shape_combine_region(new Cairo.Region()));

			win.show_all();

			int64 start = GLib.get_monotonic_time();
			Timeout.add(16, () => {
				double t = (GLib.get_monotonic_time() - start) / 1000.0 / DURATION_MS;
				if (t >= 1.0) {
					win.destroy();
					return Source.REMOVE;
				}
				alpha = START_ALPHA * (1.0 - t) * (1.0 - t);
				win.queue_draw();
				return Source.CONTINUE;
			});
		}
	}
}
