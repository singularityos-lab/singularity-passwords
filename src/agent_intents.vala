namespace Singularity.Apps.Passwords {

    internal class PasswordsIntents : Object {
        private static Store? store = null;

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static async Store connect() throws Error {
            if (store == null) {
                var s = new Store();
                yield s.connect_service();
                store = s;
            }
            return store;
        }

        private static async Gee.List<SecretEntry> all(Store s, Gee.List<SecretCollectionInfo> colls) throws Error {
            var list = new Gee.ArrayList<SecretEntry>();
            foreach (var c in colls) {
                if (c.locked) continue;
                list.add_all(yield s.items(c));
            }
            return list;
        }

        private static string keyring_label(Gee.List<SecretCollectionInfo> colls, string path) {
            foreach (var c in colls) if (c.path == path) return c.label;
            return Path.get_basename(path);
        }

        private static void entry(Json.Builder b, SecretEntry e, Gee.List<SecretCollectionInfo> colls) {
            b.begin_object();
            b.set_member_name("id").add_string_value(e.path);
            b.set_member_name("title").add_string_value(e.title);
            if (e.site != "") b.set_member_name("site").add_string_value(e.site);
            if (e.username != "") b.set_member_name("username").add_string_value(e.username);
            b.set_member_name("keyring").add_string_value(keyring_label(colls, e.collection));
            if (e.modified > 0) b.set_member_name("modified").add_string_value(new DateTime.from_unix_local((int64) e.modified).format_iso8601());
            b.end_object();
        }

        private static async SecretEntry find(Store s, Gee.List<SecretCollectionInfo> colls, string id) throws Error {
            if (id == "") throw new IOError.INVALID_ARGUMENT("give the id from passwords_search");
            foreach (var e in yield all(s, colls)) if (e.path == id) return e;
            throw new IOError.NOT_FOUND("no saved password %s, or its keyring is locked", id);
        }

        private static bool matches(SecretEntry e, string q) {
            if (q == "") return true;
            return e.title.casefold().contains(q) || e.site.casefold().contains(q) || e.username.casefold().contains(q);
        }

        private static void clipboard(Json.Builder b, string value) {
            b.set_member_name("private").begin_object();
            b.set_member_name("clipboard").begin_object();
            b.set_member_name("text").add_string_value(value);
            b.set_member_name("sensitive").add_boolean_value(true);
            b.set_member_name("clear_after").add_int_value(PasswordsApp.CLEAR_SECONDS);
            b.end_object();
            b.end_object();
        }

        private static async void search(PasswordsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                var s = yield connect();
                var colls = yield s.collections();
                string q = text(args, "query").casefold();
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("passwords").begin_array();
                int n = 0;
                foreach (var e in yield all(s, colls)) {
                    if (!e.is_login && q == "") continue;
                    if (!matches(e, q)) continue;
                    if (n++ < 50) entry(b, e, colls);
                }
                b.end_array();
                b.set_member_name("total").add_int_value(n);
                b.set_member_name("locked_keyrings").begin_array();
                foreach (var c in colls) if (c.locked) b.add_string_value(c.label);
                b.end_array();
                b.set_member_name("note").add_string_value("passwords are never shown here; passwords_copy puts one on the clipboard");
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void copy_entry(PasswordsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                var s = yield connect();
                var colls = yield s.collections();
                var e = yield find(s, colls, text(args, "id"));
                string field = text(args, "field") == "username" ? "username" : "password";
                var b = new Json.Builder();
                b.begin_object();
                if (field == "username") {
                    if (e.username == "") throw new IOError.NOT_FOUND("%s has no username", e.title);
                    clipboard(b, e.username);
                } else {
                    string secret = yield s.secret(e);
                    clipboard(b, secret);
                    secret = "";
                }
                b.set_member_name("copied").add_string_value(field);
                b.set_member_name("title").add_string_value(e.title);
                b.set_member_name("clears_in_seconds").add_int_value(PasswordsApp.CLEAR_SECONDS);
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void add(PasswordsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string title = text(args, "title");
                string url = text(args, "url");
                if (title == "" && url == "") throw new IOError.INVALID_ARGUMENT("give a title or a site");
                var s = yield connect();
                var colls = yield s.collections();
                SecretCollectionInfo? target = null;
                foreach (var c in colls) if (c.is_default) target = c;
                if (target == null && colls.size > 0) target = colls[0];
                if (target == null) throw new IOError.NOT_FOUND("there is no keyring");
                if (target.locked) throw new IOError.PERMISSION_DENIED("the %s keyring is locked; unlock it in Passwords", target.label);
                int length = args.has_member("length") ? (int) args.get_int_member("length").clamp(12, 64) : 20;
                bool symbols = !args.has_member("symbols") || args.get_boolean_member("symbols");
                string password = Generator.password(length, true, true, symbols);
                var attrs = new HashTable<string, string>(str_hash, str_equal);
                attrs["xdg:schema"] = Store.SCHEMA;
                if (url != "") attrs["url"] = url;
                if (text(args, "username") != "") attrs["username"] = text(args, "username");
                string path = yield s.create(target, title != "" ? title : url, attrs, password);
                var created = yield find(s, colls, path);
                var b = new Json.Builder();
                b.begin_object();
                clipboard(b, password);
                password = "";
                b.set_member_name("saved");
                entry(b, created, colls);
                b.set_member_name("password").add_string_value("generated, %d characters, copied to the clipboard for %u seconds".printf(length, PasswordsApp.CLEAR_SECONDS));
                b.set_member_name("undo").add_string_value("passwords_delete with id " + path);
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void remove(PasswordsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                var s = yield connect();
                var colls = yield s.collections();
                var e = yield find(s, colls, text(args, "id"));
                yield s.remove(e);
                bool gone = true;
                foreach (var x in yield all(s, colls)) if (x.path == e.path) gone = false;
                if (!gone) throw new IOError.FAILED("the password is still saved");
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("deleted").add_string_value(e.title);
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void audit(PasswordsApp app, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                var s = yield connect();
                var colls = yield s.collections();
                var poor = new Gee.ArrayList<SecretEntry>();
                var groups = new Gee.HashMap<string, Gee.ArrayList<SecretEntry>>();
                int checked_count = 0;
                foreach (var e in yield all(s, colls)) {
                    if (!e.is_login) continue;
                    string secret = yield s.secret(e);
                    if (secret == "") continue;
                    checked_count++;
                    Strength strength = Meter.rate(secret);
                    if (strength == Strength.VERY_WEAK || strength == Strength.WEAK) poor.add(e);
                    string digest = Checksum.compute_for_string(ChecksumType.SHA256, secret);
                    secret = "";
                    if (!groups.has_key(digest)) groups[digest] = new Gee.ArrayList<SecretEntry>();
                    groups[digest].add(e);
                }
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("checked").add_int_value(checked_count);
                b.set_member_name("weak").begin_array();
                foreach (var e in poor) entry(b, e, colls);
                b.end_array();
                b.set_member_name("reused").begin_array();
                foreach (var g in groups.values) {
                    if (g.size < 2) continue;
                    b.begin_array();
                    foreach (var e in g) entry(b, e, colls);
                    b.end_array();
                }
                b.end_array();
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        internal static void install(PasswordsApp app) {
            var agent = app.agent;
            agent.add_async_intent("passwords_search", "Find saved passwords by title, site or username. Only names, sites and usernames come back, never a password.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    search.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("passwords_copy", "Copy a saved password (or its username) to the clipboard for the person to paste; it clears itself after 30 seconds. The value is never returned.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"field\":{\"type\":\"string\",\"enum\":[\"password\",\"username\"]}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    copy_entry.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("passwords_add", "Save a new login with a freshly generated strong password and copy it to the clipboard. The password is never returned.",
                "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"url\":{\"type\":\"string\"},\"username\":{\"type\":\"string\"},\"length\":{\"type\":\"integer\"},\"symbols\":{\"type\":\"boolean\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    add.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("passwords_delete", "Delete a saved password. It cannot be brought back.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    remove.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("passwords_audit", "Which saved logins have weak passwords and which share the same password, without revealing any of them.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    audit.begin(app, (owned) reply);
                });
        }
    }
}
