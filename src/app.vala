using Gtk;

namespace Singularity.Apps.Passwords {

    public class PasswordsApp : Singularity.Application {
        public const uint CLEAR_SECONDS = 30;
        private PasswordSearch search;
        private Singularity.DockMenu dock_menu;
        private bool generate_pending;

        public PasswordsApp () {
            Object (application_id: "dev.sinty.passwords", flags: ApplicationFlags.DEFAULT_FLAGS);
            add_main_option ("generate-password", 0, OptionFlags.NONE, OptionArg.NONE, _("Generate a new password to copy"), null);
            search = new PasswordSearch (this);
            search.export (this);
            dock_menu = new Singularity.DockMenu ("dev.sinty.passwords");
            dock_menu.set_reply_func ((id) => {
                if (id != "generate-password") return null;
                return Singularity.SearchActivationReply.copy (Generator.password (GenerateDialog.LENGTH, true, true, true), true, CLEAR_SECONDS);
            });
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("generate-password")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("passwords: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("generate-password", null);
                return 0;
            }
            generate_pending = true;
            return -1;
        }

        public static Gdk.ContentProvider secret_content (string text) {
            return new Gdk.ContentProvider.union ({
                new Gdk.ContentProvider.for_value (text),
                new Gdk.ContentProvider.for_bytes ("x-kde-passwordManagerHint", new Bytes ("secret".data))
            });
        }

        public void copy_secret (Gdk.Clipboard clipboard, string text) {
            var provider = secret_content (text);
            clipboard.set_content (provider);
            hold ();
            Timeout.add_seconds (CLEAR_SECONDS, () => {
                if (clipboard.get_content () == provider) clipboard.set_content (null);
                release ();
                return Source.REMOVE;
            });
        }

        protected override void startup () {
            base.startup ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("New Password…"), "win.new");
            f1.append (_("New Keyring…"), "win.new-keyring");
            file_menu.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Import from CSV…"), "win.import");
            f2.append (_("Export to CSV…"), "win.export");
            file_menu.append_section (null, f2);
            var f3 = new GLib.Menu ();
            f3.append (_("Lock Keyring"), "win.lock");
            f3.append (_("Unlock Keyring"), "win.unlock");
            file_menu.append_section (null, f3);
            var f4 = new GLib.Menu ();
            f4.append (_("Close Window"), "win.close");
            f4.append (_("Quit"), "app.quit");
            file_menu.append_section (null, f4);
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Copy Username"), "win.copy-username");
            e1.append (_("Copy Password"), "win.copy-password");
            edit_menu.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Edit Password…"), "win.edit");
            e2.append (_("Delete Password…"), "win.delete");
            edit_menu.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Find"), "win.find");
            edit_menu.append_section (null, e3);
            var e4 = new GLib.Menu ();
            e4.append (_("Settings"), "app.settings");
            edit_menu.append_section (null, e4);
            menu.append_submenu (_("Edit"), edit_menu);
            var view_menu = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("All Items"), "win.filter::all");
            v1.append (_("Websites"), "win.filter::logins");
            v1.append (_("Apps and Networks"), "win.filter::other");
            view_menu.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Show Sidebar"), "win.sidebar");
            view_menu.append_section (null, v2);
            menu.append_submenu (_("View"), view_menu);
            set_menubar (menu);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.passwords");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var generate_action = new SimpleAction ("generate-password", null);
            generate_action.activate.connect (() => new GenerateDialog (this).present ());
            add_action (generate_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.new", { "<Control>n" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.lock", { "<Control>l" });
            set_accels_for_action ("win.unlock", { "<Control>l" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.sidebar", { "F9" });
        }

        public override void activate () {
            if (generate_pending) {
                generate_pending = false;
                new GenerateDialog (this).present ();
                return;
            }
            PasswordsWindow? w = null;
            foreach (var win in get_windows ()) {
                if (win is PasswordsWindow) w = (PasswordsWindow) win;
            }
            if (w == null) w = new PasswordsWindow (this);
            w.present ();
        }

        public void error (Gtk.Window parent, string title, string message) {
            var dlg = new Singularity.Widgets.ConfirmDialog.message (this, title, "dialog-error-symbolic", message);
            dlg.transient_for = parent;
            dlg.present ();
        }

        private const string CSS = """
.pw-list {
    background: transparent;
    padding: 0 12px 12px 12px;
}

.pw-list > row {
    border-radius: 12px;
    padding: 0;
}

.pw-row > box {
    padding: 8px 10px;
}

.pw-list > row:selected {
    background-color: alpha(@accent_bg_color, 0.18);
    color: inherit;
}

.pw-avatar {
    border-radius: 99px;
    color: white;
    font-weight: 700;
}

.pw-panel {
    padding: 18px;
    border-radius: 20px;
    background-color: alpha(@window_fg_color, 0.05);
}

.pw-field {
    padding: 10px 12px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.05);
}

.pw-secret {
    font-family: monospace;
    letter-spacing: 1px;
}

.pw-entry {
    font-family: monospace;
    border-radius: 12px;
}

.pw-notes {
    border-radius: 12px;
    padding: 8px;
    background-color: alpha(@window_fg_color, 0.05);
}

.pw-meter trough {
    min-height: 6px;
    border-radius: 99px;
}

.pw-meter block.filled {
    border-radius: 99px;
}

.pw-meter.level-0 block.filled,
.pw-meter.level-1 block.filled {
    background-color: @error_color;
}

.pw-meter.level-2 block.filled {
    background-color: @warning_color;
}

.pw-meter.level-3 block.filled,
.pw-meter.level-4 block.filled {
    background-color: @success_color;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-passwords", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-passwords", "UTF-8");
        Intl.textdomain ("singularity-passwords");
        return new PasswordsApp ().run (args);
    }
}
