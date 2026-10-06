using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Passwords {

    public class PasswordsWindow : Singularity.Widgets.Window {
        private PasswordsApp app;
        private Store store;
        private Gee.List<SecretCollectionInfo> collections = new Gee.ArrayList<SecretCollectionInfo> ();
        private Gee.List<SecretEntry> entries = new Gee.ArrayList<SecretEntry> ();
        private SecretCollectionInfo? current;
        private string filter = "all";
        private string query = "";
        private SecretEntry? shown;
        private string? shown_secret;

        private AppSidebar sidebar;
        private Box sidebar_box;
        private Stack stack;
        private WelcomePage locked_page;
        private StatusPage empty_page;
        private WelcomePage start_page;
        private Box header;
        private StatusPage error_page;
        private ListBox list;
        private Singularity.Animation.ListAnimator animator;
        private Label title_label;
        private Label subtitle_label;
        private Revealer panel_revealer;
        private Box panel_fields;
        private Label detail_title;
        private Label detail_sub;
        private Label avatar_letter;
        private Button lock_bubble;
        private Button add_bubble;
        private Button more_bubble;
        private SearchBubble search;
        private uint clear_clip_id;
        private uint refresh_id;
        private bool failed;

        public PasswordsWindow (PasswordsApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1080, 720);
            set_title (_("Passwords"));
            store = new Store ();

            sidebar = new AppSidebar (230);
            sidebar_box = new Box (Orientation.VERTICAL, 2);
            sidebar_box.valign = Align.START;

            sidebar.box.append (sidebar_box);
            set_sidebar (sidebar);
            set_sidebar_visible (true);

            search = add_bubble_search (_("Search Passwords"), (t) => {
                query = t.strip ().casefold ();
                fill_list ();
            });
            search.entry.input_hints = InputHints.NO_SPELLCHECK;
            add_bubble = add_bubble_icon ("list-add-symbolic", _("New Password (Ctrl+N)"), () => edit_dialog (null));
            lock_bubble = add_bubble_icon ("changes-prevent-symbolic", _("Lock"), () => toggle_lock.begin ());
            more_bubble = add_bubble_icon ("view-more-symbolic", _("More"), () => show_more_menu ());

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;

            locked_page = new WelcomePage ();
            locked_page.app_icon_name = "dev.sinty.passwords";
            locked_page.title = _("Passwords");
            locked_page.subtitle = _("Your passwords are kept in the Singularity keyring, encrypted with your login password.");
            locked_page.add_action ("changes-prevent", _("Unlock"), _("Show the passwords in this keyring"), () => toggle_lock.begin ());
            locked_page.add_action ("text-csv", _("Import Passwords"), _("From a CSV file exported by a browser or a password manager"), () => import_csv ());
            stack.add_named (locked_page, "locked");

            empty_page = new StatusPage ();
            empty_page.icon_name = "system-search";
            empty_page.title = _("No Results");
            var clear = new Button.with_label (_("Clear Search"));
            clear.add_css_class ("pill");
            clear.add_css_class ("suggested-action");
            clear.halign = Align.CENTER;
            clear.clicked.connect (() => search.clear ());
            empty_page.child = clear;
            var none_page = new WelcomePage ();
            none_page.is_section = true;
            none_page.app_icon_name = "dev.sinty.passwords";
            none_page.title = _("Nothing Here Yet");
            none_page.subtitle = _("There is nothing in this category yet.");
            none_page.add_action ("dialog-password", _("Add a Password"), _("Save a login with a strong generated password"), () => edit_dialog (null));
            none_page.add_action ("text-csv", _("Import Passwords"), _("From a CSV file exported by a browser or a password manager"), () => import_csv ());
            start_page = new WelcomePage ();
            start_page.app_icon_name = "dev.sinty.passwords";
            start_page.title = _("Passwords");
            start_page.subtitle = _("Keep your logins in the Singularity keyring, encrypted and always at hand.");
            start_page.add_action ("dialog-password", _("Add a Password"), _("Save a login with a strong generated password"), () => edit_dialog (null));
            start_page.add_action ("text-csv", _("Import Passwords"), _("From a CSV file exported by a browser or a password manager"), () => import_csv ());

            error_page = new StatusPage ();
            error_page.icon_name = "dialog-error";
            error_page.title = _("The Keyring Is Not Available");
            var retry = new Button.with_label (_("Try Again"));
            retry.add_css_class ("pill");
            retry.add_css_class ("suggested-action");
            retry.halign = Align.CENTER;
            retry.clicked.connect (() => {
                failed = false;
                start.begin ();
            });
            error_page.child = retry;
            stack.add_named (error_page, "error");

            var content = new Box (Orientation.HORIZONTAL, 0);
            var main = new Box (Orientation.VERTICAL, 0);
            main.hexpand = true;
            header = new Box (Orientation.VERTICAL, 2);
            header.margin_start = 24;
            header.margin_end = 24;
            header.margin_top = 16;
            header.margin_bottom = 10;
            Singularity.Widgets.apply_view_edge (header);
            title_label = new Label ("");
            title_label.xalign = 0;
            title_label.add_css_class ("title-2");
            subtitle_label = new Label ("");
            subtitle_label.xalign = 0;
            subtitle_label.add_css_class ("dim-label");
            header.append (title_label);
            header.append (subtitle_label);
            main.append (header);

            var inner = new Stack ();
            list = new ListBox ();
            animator = new Singularity.Animation.ListAnimator (list);
            list.add_css_class ("pw-list");
            list.selection_mode = SelectionMode.SINGLE;
            list.row_selected.connect ((row) => {
                if (row == null) return;
                var e = row.get_data<SecretEntry> ("entry");
                if (e != null) show_entry.begin (e);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = list;
            inner.add_named (scroll, "list");
            inner.add_named (empty_page, "empty");
            inner.add_named (none_page, "none");
            inner.add_named (start_page, "start");
            inner.vexpand = true;
            main.append (inner);
            list.set_data<Stack> ("inner", inner);
            content.append (main);

            panel_revealer = new Revealer ();
            panel_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
            panel_revealer.child = build_panel ();
            panel_revealer.hexpand = false;
            panel_revealer.visible = false;
            panel_revealer.notify["child-revealed"].connect (() => {
                if (!panel_revealer.reveal_child && !panel_revealer.child_revealed) panel_revealer.visible = false;
            });
            content.append (panel_revealer);
            stack.add_named (content, "items");
            set_content (stack);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                if (ctrl && keyval == Gdk.Key.f) {
                    search.grab_focus_entry ();
                    return true;
                }
                if (ctrl && keyval == Gdk.Key.n && current != null && !current.locked) {
                    edit_dialog (null);
                    return true;
                }
                if (ctrl && keyval == Gdk.Key.l) {
                    toggle_lock.begin ();
                    return true;
                }
                if (keyval == Gdk.Key.Escape && panel_revealer.reveal_child) {
                    close_panel ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
            install_actions ();
            close_request.connect (() => {
                if (clear_clip_id != 0) {
                    Source.remove (clear_clip_id);
                    get_clipboard ().set_text ("");
                }
                return false;
            });

            start.begin ();
        }

        private async void start () {
            try {
                yield store.connect_service ();
                store.changed.connect (() => {
                    if (refresh_id != 0) Source.remove (refresh_id);
                    refresh_id = Timeout.add (250, () => {
                        refresh_id = 0;
                        reload.begin ();
                        return Source.REMOVE;
                    });
                });
                yield reload ();
            } catch (Error e) {
                show_error (e.message);
            }
        }

        private void show_error (string message) {
            error_page.description = _("Singularity Keyring did not answer: %s").printf (message);
            stack.visible_child_name = "error";
            add_bubble.visible = lock_bubble.visible = more_bubble.visible = search.visible = false;
            failed = true;
            sync_actions ();
        }

        private void action (string name, owned ActionHandler handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => handler ());
            add_action (a);
        }

        private void install_actions () {
            action ("new", () => edit_dialog (null));
            action ("new-keyring", () => new_keyring ());
            action ("import", () => import_csv ());
            action ("export", () => export_csv.begin ());
            action ("lock", () => toggle_lock.begin ());
            action ("unlock", () => toggle_lock.begin ());
            action ("close", () => close ());
            action ("copy-username", () => {
                if (shown != null) copy_text (shown.username, false);
            });
            action ("copy-password", () => {
                if (shown != null) copy_secret.begin (shown);
            });
            action ("edit", () => {
                if (shown != null) edit_dialog (shown);
            });
            action ("delete", () => {
                if (shown != null) confirm_delete (shown);
            });
            action ("find", () => search.grab_focus_entry ());
            action ("sidebar", () => set_sidebar_visible (!get_sidebar_visible ()));
            var filter_action = new SimpleAction.stateful ("filter", VariantType.STRING, new Variant.string (filter));
            filter_action.activate.connect ((v) => {
                filter = v.get_string ();
                fill_sidebar ();
                fill_list ();
                sync_actions ();
            });
            add_action (filter_action);
            sync_actions ();
        }

        private void enable_action (string name, bool on) {
            var a = lookup_action (name) as SimpleAction;
            if (a != null) a.set_enabled (on);
        }

        private void sync_actions () {
            bool open = !failed && current != null && !current.locked;
            enable_action ("new", open);
            enable_action ("new-keyring", !failed);
            enable_action ("import", !failed);
            enable_action ("export", open);
            enable_action ("lock", open);
            enable_action ("unlock", !failed && current != null && current.locked);
            enable_action ("copy-username", open && shown != null && shown.username != "");
            enable_action ("copy-password", open && shown != null);
            enable_action ("edit", open && shown != null);
            enable_action ("delete", open && shown != null);
            enable_action ("find", open);
            enable_action ("filter", open);
            var f = lookup_action ("filter") as SimpleAction;
            if (f != null && f.get_state ().get_string () != filter) f.set_state (new Variant.string (filter));
        }

        private async void reload () {
            string? keep = current != null ? current.path : null;
            try {
                collections = yield store.collections ();
            } catch (Error e) {
                show_error (e.message);
                return;
            }
            current = null;
            foreach (var c in collections) if (c.path == keep) current = c;
            if (current == null && collections.size > 0) current = collections[0];
            entries = new Gee.ArrayList<SecretEntry> ();
            if (current != null && !current.locked) {
                try {
                    entries = yield store.items (current);
                } catch (Error e) {
                }
            }
            entries.sort ((a, b) => a.title.casefold ().collate (b.title.casefold ()));
            fill_sidebar ();
            update_state ();
            fill_list ();
            if (shown != null) {
                SecretEntry? again = null;
                foreach (var e in entries) if (e.path == shown.path) again = e;
                if (again == null) close_panel ();
                else show_entry.begin (again);
            }
        }

        private void update_state () {
            bool locked = current == null || current.locked;
            add_bubble.visible = !locked;
            search.visible = !locked;
            lock_bubble.visible = current != null;
            more_bubble.visible = true;
            lock_bubble.icon_name = locked ? "changes-allow-symbolic" : "changes-prevent-symbolic";
            lock_bubble.tooltip_text = locked ? _("Unlock (Ctrl+L)") : _("Lock (Ctrl+L)");
            if (current == null) {
                locked_page.subtitle = _("There is no keyring yet. Create one to keep your passwords.");
                stack.visible_child_name = "locked";
            } else if (locked) {
                locked_page.subtitle = _("\"%s\" is locked. Unlock it with your password to see what it keeps.").printf (current.label);
                stack.visible_child_name = "locked";
                close_panel ();
            } else {
                stack.visible_child_name = "items";
            }
            sync_actions ();
        }

        private int count (string f) {
            int n = 0;
            foreach (var e in entries) if (matches_filter (e, f)) n++;
            return n;
        }

        private static bool matches_filter (SecretEntry e, string f) {
            switch (f) {
                case "logins": return e.is_login;
                case "other": return !e.is_login;
                default: return true;
            }
        }

        private Widget sidebar_row (string icon, string label, int n, bool active) {
            var row = new SidebarRow (icon, label);
            row.set_active (active);
            if (n >= 0) {
                var box = row.get_child () as Box;
                if (box != null) {
                    var c = new Label (n.to_string ());
                    c.add_css_class ("dim-label");
                    c.add_css_class ("caption");
                    c.hexpand = true;
                    c.halign = Align.END;
                    box.append (c);
                }
            }
            return row;
        }

        private void fill_sidebar () {
            Widget? child;
            while ((child = sidebar_box.get_first_child ()) != null) sidebar_box.remove (child);
            bool unlocked = current != null && !current.locked;
            if (unlocked) {
                sidebar_box.append (new SidebarSectionLabel (_("Passwords")));
                string[] ids = { "all", "logins", "other" };
                string[] icons = { "view-list-symbolic", "web-browser-symbolic", "application-x-executable-symbolic" };
                string[] labels = { _("All Items"), _("Websites"), _("Apps and Networks") };
                for (int i = 0; i < ids.length; i++) {
                    string id = ids[i];
                    var row = sidebar_row (icons[i], labels[i], count (id), filter == id) as Button;
                    row.clicked.connect (() => {
                        filter = id;
                        fill_sidebar ();
                        fill_list ();
                        sync_actions ();
                    });
                    sidebar_box.append (row);
                }
            }
            sidebar_box.append (new SidebarSectionLabel (_("Keyrings")));
            foreach (var c in collections) {
                var coll = c;
                var row = sidebar_row (coll.locked ? "changes-prevent-symbolic" : "dialog-password-symbolic", coll.label, -1, coll == current) as Button;
                row.clicked.connect (() => {
                    current = coll;
                    filter = "all";
                    reload_items.begin ();
                });
                var right = new GestureClick ();
                right.button = Gdk.BUTTON_SECONDARY;
                right.pressed.connect ((n, x, y) => keyring_menu (coll, row));
                row.add_controller (right);
                sidebar_box.append (row);
            }
            var add = new SidebarRow ("list-add-symbolic", _("New Keyring"));
            add.clicked.connect (() => new_keyring ());
            sidebar_box.append (add);
        }

        private async void reload_items () {
            entries = new Gee.ArrayList<SecretEntry> ();
            if (current != null && !current.locked) {
                try {
                    entries = yield store.items (current);
                } catch (Error e) {
                }
            }
            entries.sort ((a, b) => a.title.casefold ().collate (b.title.casefold ()));
            close_panel ();
            fill_sidebar ();
            update_state ();
            fill_list ();
        }

        private static string initial (string s) {
            string t = s.strip ();
            if (t == "") return "?";
            return t.get_char (0).toupper ().to_string ();
        }

        private static string color_for (string s) {
            string[] colors = { "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#4a3aa7", "#e34948", "#199e70" };
            return colors[s.hash () % colors.length];
        }

        private Widget avatar (string text, int size) {
            var l = new Label (initial (text));
            l.add_css_class ("pw-avatar");
            l.set_size_request (size, size);
            l.valign = Align.CENTER;
            var css = new CssProvider ();
            css.load_from_string ("label { background-color: %s; font-size: %dpx; }".printf (color_for (text), size / 2));
            l.get_style_context ().add_provider (css, STYLE_PROVIDER_PRIORITY_USER + 5);
            return l;
        }

        private void fill_list () {
            animator.rebuild (fill_rows);
        }

        private void fill_rows () {
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            var inner = list.get_data<Stack> ("inner");
            int n = 0;
            foreach (var e in entries) {
                if (!matches_filter (e, filter)) continue;
                if (query != "") {
                    string hay = (e.title + " " + e.username + " " + e.url + " " + e.notes).casefold ();
                    if (!hay.contains (query)) continue;
                }
                n++;
                var row = new ListBoxRow ();
                row.set_data<SecretEntry> ("entry", e);
                row.add_css_class ("pw-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                box.append (avatar (e.site != "" ? e.site : e.title, 36));
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                texts.valign = Align.CENTER;
                var t = new Label (e.title);
                t.xalign = 0;
                t.ellipsize = Pango.EllipsizeMode.END;
                t.add_css_class ("heading");
                texts.append (t);
                string sub = e.username != "" ? e.username : (e.site != "" ? e.site : (e.item_type != "" ? e.item_type : ""));
                if (sub != "") {
                    var s = new Label (sub);
                    s.xalign = 0;
                    s.ellipsize = Pango.EllipsizeMode.END;
                    s.add_css_class ("dim-label");
                    s.add_css_class ("caption");
                    texts.append (s);
                }
                box.append (texts);
                var copy = new Button.from_icon_name ("edit-copy-symbolic");
                copy.add_css_class ("flat");
                copy.add_css_class ("circular");
                copy.valign = Align.CENTER;
                copy.tooltip_text = _("Copy Password");
                copy.clicked.connect (() => copy_secret.begin (e));
                box.append (copy);
                row.child = Singularity.Animation.ListAnimator.wrap (box);
                Singularity.Animation.ListAnimator.set_key (row, e.path);
                list.append (row);
            }
            string[] titles = { _("All Items"), _("Websites"), _("Apps and Networks") };
            string[] ids = { "all", "logins", "other" };
            for (int i = 0; i < ids.length; i++) if (ids[i] == filter) title_label.label = titles[i];
            subtitle_label.label = current != null ? "%s  ·  %s".printf (current.label, ngettext ("%d item", "%d items", n).printf (n)) : "";
            header.visible = !(n == 0 && query == "" && filter == "all");
            if (n == 0 && query == "" && filter == "all") {
                inner.visible_child_name = "start";
            } else if (n == 0 && query == "") {
                inner.visible_child_name = "none";
            } else if (n == 0) {
                empty_page.description = _("Nothing matches \"%s\".").printf (query);
                inner.visible_child_name = "empty";
            } else {
                inner.visible_child_name = "list";
            }
        }

        private Widget build_panel () {
            var outer = new Box (Orientation.VERTICAL, 0);
            outer.set_size_request (360, -1);
            outer.margin_end = 16;
            outer.margin_bottom = 16;
            Singularity.Widgets.apply_view_edge (outer);
            var panel = new Box (Orientation.VERTICAL, 14);
            panel.add_css_class ("pw-panel");
            panel.vexpand = true;
            var top = new Box (Orientation.HORIZONTAL, 12);
            var av = new Box (Orientation.HORIZONTAL, 0);
            av.set_size_request (48, 48);
            avatar_letter = new Label ("");
            av.append (avatar_letter);
            top.append (av);
            var names = new Box (Orientation.VERTICAL, 2);
            names.hexpand = true;
            names.valign = Align.CENTER;
            detail_title = new Label ("");
            detail_title.xalign = 0;
            detail_title.wrap = true;
            detail_title.add_css_class ("title-3");
            detail_sub = new Label ("");
            detail_sub.xalign = 0;
            detail_sub.ellipsize = Pango.EllipsizeMode.END;
            detail_sub.add_css_class ("dim-label");
            names.append (detail_title);
            names.append (detail_sub);
            top.append (names);
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.add_css_class ("flat");
            close.add_css_class ("circular");
            close.valign = Align.START;
            close.tooltip_text = _("Close");
            close.clicked.connect (close_panel);
            top.append (close);
            panel.append (top);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            panel_fields = new Box (Orientation.VERTICAL, 12);
            scroll.child = panel_fields;
            panel.append (scroll);
            var actions = new Box (Orientation.HORIZONTAL, 8);
            var edit = new Button.with_label (_("Edit"));
            edit.hexpand = true;
            edit.clicked.connect (() => {
                if (shown != null) edit_dialog (shown);
            });
            var del = new Button.with_label (_("Delete"));
            del.add_css_class ("destructive-action");
            del.hexpand = true;
            del.clicked.connect (() => {
                if (shown != null) confirm_delete (shown);
            });
            actions.append (edit);
            actions.append (del);
            panel.append (actions);
            outer.append (panel);
            return outer;
        }

        private void close_panel () {
            panel_revealer.reveal_child = false;
            shown = null;
            shown_secret = null;
            list.unselect_all ();
            sync_actions ();
        }

        private Widget field (string title, string value, bool secret, string? link = null) {
            var box = new Box (Orientation.VERTICAL, 4);
            box.add_css_class ("pw-field");
            var t = new Label (title);
            t.xalign = 0;
            t.add_css_class ("caption");
            t.add_css_class ("dim-label");
            box.append (t);
            var row = new Box (Orientation.HORIZONTAL, 4);
            var v = new Label (secret ? string.nfill (int.min (value.char_count (), 16), '*') : value);
            v.xalign = 0;
            v.hexpand = true;
            v.wrap = !secret;
            v.wrap_mode = Pango.WrapMode.WORD_CHAR;
            v.selectable = !secret;
            if (secret) v.add_css_class ("pw-secret");
            row.append (v);
            if (secret) {
                var eye = new ToggleButton ();
                eye.icon_name = "view-reveal-symbolic";
                eye.add_css_class ("flat");
                eye.add_css_class ("circular");
                eye.tooltip_text = _("Show");
                eye.toggled.connect (() => {
                    v.label = eye.active ? value : string.nfill (int.min (value.char_count (), 16), '*');
                    v.selectable = eye.active;
                    eye.icon_name = eye.active ? "view-conceal-symbolic" : "view-reveal-symbolic";
                    eye.tooltip_text = eye.active ? _("Hide") : _("Show");
                });
                row.append (eye);
            }
            if (link != null) {
                var open = new Button.from_icon_name ("web-browser-symbolic");
                open.add_css_class ("flat");
                open.add_css_class ("circular");
                open.tooltip_text = _("Open Website");
                open.clicked.connect (() => {
                    string target = link.contains ("://") ? link : "https://" + link;
                    new UriLauncher (target).launch.begin (this, null);
                });
                row.append (open);
            }
            var copy = new Button.from_icon_name ("edit-copy-symbolic");
            copy.add_css_class ("flat");
            copy.add_css_class ("circular");
            copy.tooltip_text = _("Copy");
            copy.clicked.connect (() => copy_text (value, secret));
            row.append (copy);
            box.append (row);
            return box;
        }

        private async void show_entry (SecretEntry e) {
            shown = e;
            string secret = "";
            try {
                secret = yield store.secret (e);
            } catch (Error err) {
                secret = "";
            }
            if (shown != e) return;
            shown_secret = secret;
            var old = avatar_letter.get_parent () as Box;
            var fresh = avatar (e.site != "" ? e.site : e.title, 48);
            old.remove (avatar_letter);
            avatar_letter = (Label) fresh;
            old.append (avatar_letter);
            detail_title.label = e.title;
            detail_sub.label = e.site != "" ? e.site : (e.attributes["xdg:schema"] ?? "");
            Widget? child;
            while ((child = panel_fields.get_first_child ()) != null) panel_fields.remove (child);
            if (e.username != "") panel_fields.append (field (_("Username"), e.username, false));
            panel_fields.append (field (_("Password"), secret, true));
            var strength = Meter.rate (secret);
            var meter = new LevelBar.for_interval (0, 4);
            meter.value = (int) strength + (secret != "" ? 0.5 : 0);
            meter.add_css_class ("pw-meter");
            meter.add_css_class ("level-%d".printf ((int) strength));
            var ml = new Label (secret == "" ? _("Empty password") : strength.label ());
            ml.xalign = 0;
            ml.add_css_class ("caption");
            ml.add_css_class ("dim-label");
            panel_fields.append (meter);
            panel_fields.append (ml);
            if (e.url != "") panel_fields.append (field (_("Website"), e.url, false, e.url));
            if (e.notes != "") panel_fields.append (field (_("Notes"), e.notes, false));
            var extra = new Gee.TreeMap<string, string> ();
            string[] shown_keys = { "username", "user", "login", "account", "email", "username_value", "user_name", "url", "origin", "origin_url", "server", "host", "domain", "signon_realm", "uri", "address", "notes", "xdg:schema" };
            e.attributes.foreach ((k, v) => {
                if (!(k in shown_keys) && v != "") extra[k] = v;
            });
            if (extra.size > 0) {
                var exp = new Expander (_("Attributes"));
                exp.add_css_class ("pw-details");
                var grid = new Grid ();
                grid.column_spacing = 12;
                grid.row_spacing = 4;
                grid.margin_top = 6;
                int r = 0;
                foreach (var kv in extra.entries) {
                    var k = new Label (kv.key);
                    k.xalign = 0;
                    k.add_css_class ("dim-label");
                    k.add_css_class ("caption");
                    var v = new Label (kv.value);
                    v.xalign = 0;
                    v.selectable = true;
                    v.wrap = true;
                    v.wrap_mode = Pango.WrapMode.WORD_CHAR;
                    v.hexpand = true;
                    v.add_css_class ("caption");
                    grid.attach (k, 0, r);
                    grid.attach (v, 1, r);
                    r++;
                }
                exp.child = grid;
                panel_fields.append (exp);
            }
            var dates = new Label ("");
            dates.xalign = 0;
            dates.add_css_class ("caption");
            dates.add_css_class ("dim-label");
            string created = e.created > 0 ? new DateTime.from_unix_local ((int64) e.created).format ("%x") : "";
            string modified = e.modified > 0 ? new DateTime.from_unix_local ((int64) e.modified).format ("%x") : "";
            dates.label = modified != "" ? _("Created %s, changed %s").printf (created, modified) : "";
            panel_fields.append (dates);
            panel_revealer.visible = true;
            panel_revealer.reveal_child = true;
            sync_actions ();
        }

        private void copy_text (string text, bool secret) {
            if (!secret) {
                get_clipboard ().set_text (text);
                return;
            }
            get_clipboard ().set_content (PasswordsApp.secret_content (text));
            if (clear_clip_id != 0) Source.remove (clear_clip_id);
            clear_clip_id = Timeout.add_seconds (30, () => {
                clear_clip_id = 0;
                var clip = get_clipboard ();
                clip.read_text_async.begin (null, (obj, res) => {
                    try {
                        if (clip.read_text_async.end (res) == text) clip.set_text ("");
                    } catch (Error e) {
                    }
                });
                return Source.REMOVE;
            });
            toast (_("Password copied. It will be cleared from the clipboard in 30 seconds."));
        }

        private void toast (string text) {
            subtitle_label.label = text;
            Timeout.add_seconds (4, () => {
                fill_list ();
                return Source.REMOVE;
            });
        }

        private async void copy_secret (SecretEntry e) {
            try {
                copy_text (yield store.secret (e), true);
            } catch (Error err) {
                app.error (this, _("Could Not Read the Password"), err.message);
            }
        }

        private async void toggle_lock () {
            if (current == null) {
                new_keyring ();
                return;
            }
            try {
                if (current.locked) yield store.unlock (current);
                else yield store.lock (current);
            } catch (Error e) {
                if (!(e is SecretError.DISMISSED)) app.error (this, current.locked ? _("Could Not Unlock") : _("Could Not Lock"), e.message);
            }
            yield reload ();
        }

        private void keyring_menu (SecretCollectionInfo coll, Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (coll.locked ? _("Unlock") : _("Lock"), coll.locked ? "changes-allow-symbolic" : "changes-prevent-symbolic", () => {
                current = coll;
                toggle_lock.begin ();
            });
            menu.add_separator ();
            menu.add_item (_("Delete Keyring"), "user-trash-symbolic", () => {
                var dlg = new ConfirmDialog (app, _("Delete \"%s\"?").printf (coll.label), "user-trash-symbolic",
                    _("Every password in this keyring will be deleted for good. Apps that keep their passwords here will ask for them again."),
                    _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
                dlg.transient_for = this;
                dlg.response.connect ((r) => {
                    if (r != ConfirmDialog.Response.PRIMARY) return;
                    store.delete_collection.begin (coll, (o, res) => {
                        try {
                            store.delete_collection.end (res);
                        } catch (Error e) {
                            app.error (this, _("Could Not Delete"), e.message);
                        }
                        reload.begin ();
                    });
                });
                dlg.present ();
            }, "destructive");
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void new_keyring () {
            var dlg = new AppDialog (app, true);
            dlg.set_title (_("New Keyring"));
            dlg.transient_for = this;
            dlg.set_default_size (400, 240);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_bottom = 16;
            var g = new PreferencesGroup ();
            var name = new EntryRow (_("Name"));
            g.add_row (name);
            box.append (g);
            var create = new Button.with_label (_("Create"));
            create.add_css_class ("suggested-action");
            create.halign = Align.END;
            create.clicked.connect (() => {
                string label = name.text.strip ();
                if (label == "") return;
                dlg.close ();
                store.create_collection.begin (label, (o, res) => {
                    try {
                        current = store.create_collection.end (res);
                    } catch (Error e) {
                        app.error (this, _("Could Not Create the Keyring"), e.message);
                    }
                    reload.begin ();
                });
            });
            box.append (create);
            dlg.content_box.append (box);
            dlg.open_dialog ();
        }

        private void confirm_delete (SecretEntry e) {
            var dlg = new ConfirmDialog (app, _("Delete \"%s\"?").printf (e.title), "user-trash-symbolic",
                _("The password will be deleted for good."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                for (var child = list.get_first_child (); child != null; child = child.get_next_sibling ()) {
                    if (child.get_data<SecretEntry> ("entry") == e) animator.remove (child, () => {});
                }
                store.remove.begin (e, (o, res) => {
                    try {
                        store.remove.end (res);
                        close_panel ();
                    } catch (Error err) {
                        app.error (this, _("Could Not Delete"), err.message);
                    }
                    reload.begin ();
                });
            });
            dlg.present ();
        }

        private void edit_dialog (SecretEntry? e) {
            if (current == null || current.locked) return;
            var dlg = new AppDialog (app, true);
            dlg.set_title (e == null ? _("New Password") : _("Edit Password"));
            dlg.transient_for = this;
            dlg.set_default_size (460, 600);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 4;
            box.margin_bottom = 8;
            scroll.child = box;
            var g = new PreferencesGroup ();
            var name = new EntryRow (_("Name"));
            var site = new EntryRow (_("Website"));
            var user = new EntryRow (_("Username"));
            name.text = e != null ? e.label : "";
            site.text = e != null ? e.url : "";
            user.text = e != null ? e.username : "";
            g.add_row (name);
            g.add_row (site);
            g.add_row (user);
            box.append (g);

            var pw_box = new Box (Orientation.VERTICAL, 6);
            var pw_label = new Label (_("Password"));
            pw_label.xalign = 0;
            pw_label.add_css_class ("heading");
            pw_box.append (pw_label);
            var pw = new PasswordEntry ();
            pw.show_peek_icon = true;
            pw.hexpand = true;
            pw.add_css_class ("pw-entry");
            if (e != null && shown == e && shown_secret != null) pw.text = shown_secret;
            pw_box.append (pw);
            var meter = new LevelBar.for_interval (0, 4);
            meter.add_css_class ("pw-meter");
            var meter_label = new Label ("");
            meter_label.xalign = 0;
            meter_label.add_css_class ("caption");
            meter_label.add_css_class ("dim-label");
            pw_box.append (meter);
            pw_box.append (meter_label);
            box.append (pw_box);

            var gen = new PreferencesGroup (_("Generate"));
            var length = new SpinRow (_("Length"), null, 8, 64, 1, 20);
            var upper = new SwitchRow (_("Capital letters"), null, true);
            var digits = new SwitchRow (_("Numbers"), null, true);
            var symbols = new SwitchRow (_("Symbols"), null, true);
            string[] kinds = { _("Random characters"), _("Words") };
            var kind = new SelectionRow (_("Type"), kinds, kinds[0]);
            gen.add_row (kind);
            gen.add_row (length);
            gen.add_row (upper);
            gen.add_row (digits);
            gen.add_row (symbols);
            box.append (gen);
            var make = new Button.with_label (_("Generate Password"));
            make.add_css_class ("pill");
            make.halign = Align.START;
            box.append (make);

            var notes_label = new Label (_("Notes"));
            notes_label.xalign = 0;
            notes_label.add_css_class ("heading");
            box.append (notes_label);
            var notes = new TextView ();
            notes.wrap_mode = WrapMode.WORD_CHAR;
            notes.add_css_class ("pw-notes");
            notes.buffer.text = e != null ? e.notes : "";
            notes.set_size_request (-1, 80);
            box.append (notes);

            ActionHandler update_meter = () => {
                var st = Meter.rate (pw.text);
                meter.value = pw.text == "" ? 0 : (int) st + 0.5;
                foreach (string c in new string[] { "level-0", "level-1", "level-2", "level-3", "level-4" }) meter.remove_css_class (c);
                meter.add_css_class ("level-%d".printf ((int) st));
                meter_label.label = pw.text == "" ? "" : st.label ();
            };
            ActionHandler generate = () => {
                bool words = kind.current_value == kinds[1];
                length.visible = !words;
                upper.visible = digits.visible = symbols.visible = !words;
                pw.text = words ? Generator.passphrase (5) : Generator.password ((int) length.value, upper.active, digits.active, symbols.active);
            };
            pw.changed.connect (() => update_meter ());
            make.clicked.connect (() => generate ());
            kind.selected.connect ((v) => generate ());
            length.spin_btn.value_changed.connect (() => generate ());
            upper.switch_btn.notify["active"].connect (() => generate ());
            digits.switch_btn.notify["active"].connect (() => generate ());
            symbols.switch_btn.notify["active"].connect (() => generate ());
            if (e == null) generate ();
            update_meter ();

            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("suggested-action");
            bar.append (cancel);
            bar.append (save);
            save.clicked.connect (() => {
                string label = name.text.strip ();
                if (label == "") label = site.text.strip ();
                if (label == "") label = user.text.strip ();
                if (label == "") {
                    name.add_css_class ("error");
                    return;
                }
                var attrs = new HashTable<string, string> (str_hash, str_equal);
                if (e != null) e.attributes.foreach ((k, v) => attrs[k] = v);
                else attrs["xdg:schema"] = Store.SCHEMA;
                string[] user_keys = { "username", "user", "login", "account", "email", "username_value", "user_name" };
                bool set_user = false;
                foreach (string k in user_keys) if (attrs.contains (k)) {
                    attrs[k] = user.text.strip ();
                    set_user = true;
                }
                if (!set_user && user.text.strip () != "") attrs["username"] = user.text.strip ();
                string[] url_keys = { "url", "origin", "origin_url", "server", "host", "domain", "signon_realm", "uri", "address" };
                bool set_url = false;
                foreach (string k in url_keys) if (attrs.contains (k)) {
                    attrs[k] = site.text.strip ();
                    set_url = true;
                }
                if (!set_url && site.text.strip () != "") attrs["url"] = site.text.strip ();
                string n = notes.buffer.text.strip ();
                if (n != "") attrs["notes"] = n;
                else attrs.remove ("notes");
                string secret = pw.text;
                dlg.close ();
                if (e == null) {
                    store.create.begin (current, label, attrs, secret, (o, res) => {
                        try {
                            store.create.end (res);
                        } catch (Error err) {
                            app.error (this, _("Could Not Save"), err.message);
                        }
                        reload.begin ();
                    });
                } else {
                    store.update.begin (e, label, attrs, secret, (o, res) => {
                        try {
                            store.update.end (res);
                        } catch (Error err) {
                            app.error (this, _("Could Not Save"), err.message);
                        }
                        reload.begin ();
                    });
                }
            });
            dlg.content_box.append (scroll);
            dlg.content_box.append (bar);
            dlg.default_widget = save;
            dlg.open_dialog ();
            name.grab_focus ();
        }

        public delegate void ActionHandler ();

        private void show_more_menu () {
            var menu = new ContextMenu (stack);
            Graphene.Rect b;
            if (more_bubble.compute_bounds (stack, out b)) {
                var r = Gdk.Rectangle ();
                r.x = (int) b.origin.x;
                r.y = (int) b.origin.y;
                r.width = (int) b.size.width;
                r.height = (int) b.size.height;
                menu.pointing_to = r;
            }
            menu.add_item (_("Import from CSV"), "document-open-symbolic", () => import_csv ());
            if (current != null && !current.locked) menu.add_item (_("Export to CSV"), "document-save-as-symbolic", () => export_csv.begin ());
            menu.add_separator ();
            menu.add_item (_("New Keyring"), "list-add-symbolic", () => new_keyring ());
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void import_csv () {
            var dialog = new FileDialog ();
            dialog.title = _("Import Passwords");
            var filter_f = new FileFilter ();
            filter_f.name = _("CSV Files");
            filter_f.add_suffix ("csv");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter_f);
            dialog.filters = filters;
            dialog.open.begin (this, null, (o, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) import_file.begin (file);
                } catch (Error e) {
                }
            });
        }

        private async void import_file (File file) {
            try {
                if (current == null) {
                    current = yield store.create_collection (_("Login"));
                }
                if (current.locked) yield store.unlock (current);
                uint8[] data;
                yield file.load_contents_async (null, out data, null);
                var sb = new StringBuilder ();
                sb.append_len ((string) data, data.length);
                var recs = Csv.import (sb.str);
                int n = 0;
                foreach (var r in recs) {
                    var attrs = new HashTable<string, string> (str_hash, str_equal);
                    attrs["xdg:schema"] = Store.SCHEMA;
                    if (r.url != "") attrs["url"] = Csv.web_origin (r.url);
                    if (r.username != "") attrs["username"] = r.username;
                    if (r.notes != "") attrs["notes"] = r.notes;
                    yield store.create (current, r.name != "" ? r.name : r.url, attrs, r.password);
                    n++;
                }
                yield reload ();
                toast (ngettext ("%d password imported", "%d passwords imported", n).printf (n));
            } catch (Error e) {
                if (!(e is SecretError.DISMISSED)) app.error (this, _("Could Not Import"), e.message);
            }
        }

        private async void export_csv () {
            var dlg = new ConfirmDialog (app, _("Export Passwords?"), "dialog-warning-symbolic",
                _("The file will contain your passwords as plain text. Anyone who opens it can read them."),
                _("Export"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            bool go = false;
            dlg.response.connect ((r) => {
                go = r == ConfirmDialog.Response.PRIMARY;
                export_csv.callback ();
            });
            dlg.present ();
            yield;
            if (!go) return;
            var fd = new FileDialog ();
            fd.title = _("Export Passwords");
            fd.initial_name = "passwords.csv";
            try {
                var file = yield fd.save (this, null);
                if (file == null) return;
                var recs = new Gee.ArrayList<CsvRecord> ();
                foreach (var e in entries) {
                    var r = new CsvRecord ();
                    r.name = e.title;
                    r.url = e.url;
                    r.username = e.username;
                    r.notes = e.notes;
                    r.password = yield store.secret (e);
                    recs.add (r);
                }
                string text = Csv.export (recs);
                yield file.replace_contents_async (text.data, null, false, FileCreateFlags.PRIVATE | FileCreateFlags.REPLACE_DESTINATION, null, null);
                toast (ngettext ("%d password exported", "%d passwords exported", recs.size).printf (recs.size));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) app.error (this, _("Could Not Export"), e.message);
            }
        }
    }
}
