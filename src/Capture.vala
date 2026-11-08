/*
 * Screenshot applet for Budgie 10.10+ (Wayland)
 * Capture backend: grim + slurp, clipboard via wl-copy.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

namespace ScreenshotWl {

	public const string SCHEMA_ID = "io.github.budgiescreenshotwl";
	public const string RESOURCE_PATH = "/io/github/budgiescreenshotwl";

	public enum Mode {
		MONITOR,  // one monitor (click it if there are several)
		WINDOW,   // a window picked from the list
		AREA      // drag a rectangle
	}

	[DBus (name = "org.freedesktop.Notifications")]
	interface Notifications : Object {
		public abstract async uint32 notify(string app_name, uint32 replaces_id, string app_icon,
			string summary, string body, string[] actions,
			HashTable<string, Variant> hints, int32 expire_timeout) throws Error;
		public signal void action_invoked(uint32 id, string action_key);
	}

	/* Helpers shared by the popover and the capture code */
	namespace Util {
		public async void sleep(uint ms) {
			Timeout.add(ms, () => {
				sleep.callback();
				return Source.REMOVE;
			});
			yield;
		}

		public bool have(string program) {
			return Environment.find_program_in_path(program) != null;
		}

		public string save_dir(Settings settings) {
			string dir = settings.get_string("save-path").strip();
			if (dir.has_prefix("~")) {
				dir = Environment.get_home_dir() + dir.substring(1);
			}
			if (dir == "") {
				string? pics = Environment.get_user_special_dir(UserDirectory.PICTURES);
				if (pics == null) pics = Environment.get_home_dir();
				dir = Path.build_filename(pics, "Screenshots");
			}
			return dir;
		}

		/* Where "don't save" screenshots live; wiped on logout */
		public string temp_dir() {
			return Path.build_filename(Environment.get_user_runtime_dir(), "budgie-screenshot-wl");
		}

		public bool is_unsaved(string path) {
			return path.has_prefix(temp_dir() + "/");
		}

		public string unique_path(string dir, string base_name) {
			string path = Path.build_filename(dir, base_name + ".png");
			for (int i = 2; FileUtils.test(path, FileTest.EXISTS); i++) {
				path = Path.build_filename(dir, "%s (%d).png".printf(base_name, i));
			}
			return path;
		}

		/* Move an unsaved screenshot into the screenshots folder; returns the new path */
		public string save_permanently(Settings settings, string path) throws Error {
			string dir = save_dir(settings);
			DirUtils.create_with_parents(dir, 0755);
			string base_name = Path.get_basename(path);
			if (base_name.has_suffix(".png")) base_name = base_name.substring(0, base_name.length - 4);
			string dest = unique_path(dir, base_name);
			File.new_for_path(path).move(File.new_for_path(dest), FileCopyFlags.NONE);

			string[] list = {};
			foreach (var p in settings.get_strv("history")) list += (p == path) ? dest : p;
			settings.set_strv("history", list);
			return dest;
		}

		/* Known editors and the options that make Save/Copy work */
		private string[]? known_editor(string program, string path) {
			switch (Path.get_basename(program)) {
				case "satty":
					return { program, "--filename", path, "--output-filename", path, "--copy-command", "wl-copy" };
				case "swappy":
					return { program, "-f", path, "-o", path };
				default:
					return null;
			}
		}

		/* Editor argv from the setting; null (editing off) when it's empty.
		 * In the setting, %f is replaced by the file; a bare "satty" or
		 * "swappy" gets the right options; anything else gets the path appended. */
		public string[]? editor_argv(Settings settings, string path) {
			string cmd = settings.get_string("editor-command").strip();
			if (cmd != "") {
				string[] argv;
				try {
					Shell.parse_argv(cmd, out argv);
				} catch (ShellError e) {
					warning("Bad editor command: %s", e.message);
					return null;
				}
				if (argv.length == 1) {
					var known = known_editor(argv[0], path);
					if (known != null) return known;
				}
				bool placed = false;
				for (int i = 0; i < argv.length; i++) {
					if (argv[i].contains("%f")) {
						argv[i] = argv[i].replace("%f", path);
						placed = true;
					}
				}
				if (!placed) argv += path;
				return argv;
			}
			return null; // no editor set: no Edit button
		}

		public void spawn(string[] argv) {
			try {
				new Subprocess.newv(argv, SubprocessFlags.NONE);
			} catch (Error e) {
				warning("Failed to run %s: %s", argv[0], e.message);
			}
		}

		public void open_uri(string path) {
			try {
				AppInfo.launch_default_for_uri(File.new_for_path(path).get_uri(), null);
			} catch (Error e) {
				warning("Failed to open %s: %s", path, e.message);
			}
		}

		/* Highlight the file in the file manager, fall back to opening its folder */
		public void show_in_folder(string path) {
			var uri = File.new_for_path(path).get_uri();
			show_items.begin(uri, (obj, res) => {
				try {
					show_items.end(res);
				} catch (Error e) {
					open_uri(Path.get_dirname(path));
				}
			});
		}

		private async void show_items(string uri) throws Error {
			var conn = yield Bus.get(BusType.SESSION);
			yield conn.call("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
				"org.freedesktop.FileManager1", "ShowItems",
				new Variant("(ass)", new string[] { uri }, ""),
				null, DBusCallFlags.NONE, 3000, null);
		}

		public async void copy_to_clipboard(string path) throws Error {
			if (!have("wl-copy")) {
				throw new IOError.NOT_FOUND("%s", _("wl-copy not found (install wl-clipboard)"));
			}
			uint8[] data;
			FileUtils.get_data(path, out data);
			var proc = new Subprocess.newv({ "wl-copy", "--type", "image/png" },
				SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
			yield proc.communicate_async(new Bytes(data), null, null, null);
		}

		public async string run_stdout(string[] argv, out bool success) throws Error {
			var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			string? out_str;
			yield proc.communicate_utf8_async(null, null, out out_str, null);
			success = proc.get_successful();
			return out_str ?? "";
		}
	}

	public class Capture : Object {
		private Settings settings;
		private Notifications? notifications = null;
		private HashTable<uint32, string> notified = new HashTable<uint32, string>(direct_hash, direct_equal);

		public bool busy { get; private set; default = false; }
		public bool window_supported { get; private set; default = false; }
		public string window_unsupported_reason { get; private set; default = ""; }

		public signal void started();
		public signal void tick(int seconds_left);   // countdown during the delay
		public signal void taken(string path);
		public signal void finished();               // after taken/failed/cancelled
		public signal void failed(string message);

		public Capture(Settings settings) {
			this.settings = settings;
			Bus.get_proxy.begin<Notifications>(BusType.SESSION, "org.freedesktop.Notifications",
				"/org/freedesktop/Notifications", DBusProxyFlags.NONE, null, (obj, res) => {
					try {
						notifications = Bus.get_proxy.end(res);
						notifications.action_invoked.connect(on_notification_action);
					} catch (Error e) {
						warning("No notification service: %s", e.message);
					}
				});
			check_window_support.begin();
		}

		/* Window capture needs grim >= 1.5 (-T) and compositor support (labwc has it) */
		private async void check_window_support() {
			try {
				if (!Util.have("grim")) {
					window_unsupported_reason = _("%s not found").printf("grim");
					return;
				}
				bool ok;
				string help = yield Util.run_stdout({ "grim", "-h" }, out ok);
				if (!help.contains("-T")) {
					window_unsupported_reason = _("Your grim is too old for window capture (needs 1.5+)");
					return;
				}
				string helper = Path.build_filename(Config.LIBEXECDIR, "budgie-screenshot-wl-windows");
				yield Util.run_stdout({ helper, "--check" }, out ok);
				if (!ok) {
					window_unsupported_reason = _("Your compositor doesn't support capturing single windows");
					return;
				}
				window_unsupported_reason = "";
				window_supported = true;
			} catch (Error e) {
				window_unsupported_reason = e.message;
			}
		}

		public async void run(Mode mode, string? window_id = null) {
			if (busy) return;
			busy = true;
			started();

			try {
				foreach (var prog in new string[] { "grim", "slurp" }) {
					if (!Util.have(prog)) {
						throw new IOError.NOT_FOUND("%s", _("%s not found").printf(prog));
					}
				}

				// Let the popover finish hiding so it isn't in the picture
				yield Util.sleep(250);

				string? geometry = null;
				bool selected = false;
				if (mode == Mode.AREA || (mode == Mode.MONITOR && monitor_count() > 1)) {
					string[] slurp_argv = (mode == Mode.MONITOR)
						? new string[] { "slurp", "-o", "-r" }
						: new string[] { "slurp", "-d" };
					geometry = yield run_slurp(slurp_argv);
					if (geometry == null) {
						busy = false;
						finished();
						return; // user pressed Escape
					}
					selected = true;
				}

				int delay = settings.get_int("delay");
				for (int left = delay; left > 0; left--) {
					tick(left);
					yield Util.sleep(1000);
				}
				if (delay == 0 && selected) {
					yield Util.sleep(150); // let slurp's overlay disappear
				}

				bool save = settings.get_boolean("save-to-disk");
				string path = next_filename(save);
				string[] grim_argv = { "grim" };
				if (settings.get_boolean("include-pointer")) grim_argv += "-c";
				if (mode == Mode.WINDOW && window_id != null) {
					grim_argv += "-T";
					grim_argv += window_id;
				} else if (geometry != null) {
					grim_argv += "-g";
					grim_argv += geometry;
				}
				grim_argv += path;

				bool ok;
				string err_out = yield Util.run_stdout(grim_argv, out ok);
				if (!ok) {
					throw new IOError.FAILED("%s", _("grim failed: %s").printf(err_out.strip()));
				}

				if (settings.get_boolean("flash")) {
					Flash.show();
				}

				if (settings.get_boolean("play-sound") && Util.have("canberra-gtk-play")) {
					Util.spawn({ "canberra-gtk-play", "-i", "screen-capture", "-d", "screenshot" });
				}

				bool copied = false;
				if (settings.get_boolean("copy-to-clipboard") || !save) {
					try {
						yield Util.copy_to_clipboard(path);
						copied = true;
					} catch (Error e) {
						warning("Clipboard: %s", e.message);
						if (!save) throw e; // nothing would be kept at all
					}
				}

				add_to_history(path);
				notify_taken.begin(path, copied);
				taken(path);
			} catch (Error e) {
				warning("Screenshot failed: %s", e.message);
				failed(e.message);
				notify_error.begin(e.message);
			}

			busy = false;
			finished();
		}

		private int monitor_count() {
			var display = Gdk.Display.get_default();
			return display != null ? display.get_n_monitors() : 1;
		}

		/* Returns slurp's geometry string, or null if the selection was cancelled */
		private async string? run_slurp(string[] argv) throws Error {
			var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
			string? out_str;
			yield proc.communicate_utf8_async(null, null, out out_str, null);
			if (!proc.get_successful() || out_str == null || out_str.strip() == "") {
				return null;
			}
			return out_str.strip();
		}

		private string next_filename(bool save) throws Error {
			string dir = save ? Util.save_dir(settings) : Util.temp_dir();
			if (DirUtils.create_with_parents(dir, save ? 0755 : 0700) != 0) {
				throw new IOError.FAILED("%s", _("Cannot create %s").printf(dir));
			}

			string fmt = settings.get_string("filename-format");
			string? base_name = new DateTime.now_local().format(fmt);
			if (base_name == null || base_name.strip() == "") base_name = _("Screenshot");
			base_name = base_name.replace("/", "-");
			return Util.unique_path(dir, base_name);
		}

		private void add_to_history(string path) {
			int max = settings.get_int("history-size");
			string[] keep = {};
			if (max > 0) keep += path;

			foreach (var p in settings.get_strv("history")) {
				if (p == path || !FileUtils.test(p, FileTest.EXISTS)) continue;
				if (keep.length < max) {
					keep += p;
				} else if (Util.is_unsaved(p)) {
					FileUtils.unlink(p); // dropped off the list; nobody can reach it anymore
				}
			}
			// with history off, an unsaved shot still has to live until it's pasted
			if (max == 0 && Util.is_unsaved(path)) keep += path;
			settings.set_strv("history", keep);
		}

		private async void notify_taken(string path, bool copied) {
			if (notifications == null || !settings.get_boolean("show-notification")) return;

			bool unsaved = Util.is_unsaved(path);
			string[] actions = { "default", _("Open"), "open", _("Open") };
			if (unsaved) {
				actions += "save";
				actions += _("Save");
			} else {
				actions += "folder";
				actions += _("Show in folder");
			}
			if (Util.editor_argv(settings, path) != null) {
				actions += "edit";
				actions += _("Edit");
			}
			var hints = new HashTable<string, Variant>(str_hash, str_equal);
			hints.insert("image-path", new Variant.string(File.new_for_path(path).get_uri()));
			hints.insert("transient", new Variant.boolean(true));

			string body;
			if (unsaved) {
				body = _("Copied to clipboard (not saved)");
			} else {
				body = Path.get_basename(path);
				if (copied) body += "\n" + _("Copied to clipboard");
			}

			try {
				uint32 id = yield notifications.notify(_("Screenshot"), 0, "camera-photo",
					_("Screenshot taken"), body, actions, hints, 5000);
				notified.insert(id, path);
			} catch (Error e) {
				warning("Notify failed: %s", e.message);
			}
		}

		private async void notify_error(string msg) {
			if (notifications == null) return;
			var hints = new HashTable<string, Variant>(str_hash, str_equal);
			try {
				yield notifications.notify(_("Screenshot"), 0, "dialog-error",
					_("Screenshot failed"), msg, {}, hints, 5000);
			} catch (Error e) {}
		}

		private void on_notification_action(uint32 id, string action) {
			string? path = notified.get(id);
			if (path == null) return;
			notified.remove(id);
			if (!FileUtils.test(path, FileTest.EXISTS)) return;

			switch (action) {
				case "folder":
					Util.show_in_folder(path);
					break;
				case "save":
					try {
						Util.show_in_folder(Util.save_permanently(settings, path));
					} catch (Error e) {
						warning("Save failed: %s", e.message);
					}
					break;
				case "edit":
					var argv = Util.editor_argv(settings, path);
					if (argv != null) Util.spawn(argv);
					break;
				default:
					Util.open_uri(path);
					break;
			}
		}
	}
}
