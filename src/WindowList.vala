/*
 * Open windows, as reported by the budgie-screenshot-wl-windows helper.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public class WindowInfo : Object {
		public string id { get; construct; }
		public string app_id { get; construct; }
		public string title { get; construct; }

		public WindowInfo(string id, string app_id, string title) {
			Object(id: id, app_id: app_id, title: title);
		}

		public string display_title() {
			if (title != "") return title;
			if (app_id != "") return app_id;
			return _("Untitled window");
		}

		public Icon icon() {
			if (app_id != "") {
				string[] candidates = { app_id, app_id.down() };
				foreach (var c in candidates) {
					var info = new DesktopAppInfo(c + ".desktop");
					if (info != null && info.get_icon() != null) return info.get_icon();
				}
				// e.g. org.gnome.Nautilus -> nautilus, firefox -> firefox
				var parts = app_id.split(".");
				return new ThemedIcon.from_names({ app_id, app_id.down(), parts[parts.length - 1].down(),
					"application-x-executable" });
			}
			return new ThemedIcon("application-x-executable");
		}
	}

	namespace WindowList {
		public async List<WindowInfo> fetch() throws Error {
			string helper = Path.build_filename(Config.LIBEXECDIR, "budgie-screenshot-wl-windows");
			var proc = new Subprocess.newv({ helper }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
			string? out_str, err_str;
			yield proc.communicate_utf8_async(null, null, out out_str, out err_str);
			if (!proc.get_successful()) {
				throw new IOError.FAILED("%s", (err_str ?? _("Could not list windows")).strip());
			}

			var result = new List<WindowInfo>();
			foreach (var line in (out_str ?? "").split("\n")) {
				var f = line.split("\t", 3);
				if (f.length < 3 || f[0] == "") continue;
				result.append(new WindowInfo(f[0], f[1], f[2]));
			}
			result.sort((a, b) => strcmp(a.display_title().casefold(), b.display_title().casefold()));
			return result;
		}
	}
}
