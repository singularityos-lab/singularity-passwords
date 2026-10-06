namespace Singularity.Apps.Passwords {

    public errordomain SecretError {
        UNAVAILABLE,
        LOCKED,
        DISMISSED,
        FAILED
    }

    public class SecretEntry : Object {
        public string path = "";
        public string collection = "";
        public string label = "";
        public string item_type = "";
        public HashTable<string, string> attributes = new HashTable<string, string> (str_hash, str_equal);
        public uint64 created;
        public uint64 modified;

        private static string[] USER_KEYS = { "username", "user", "login", "account", "email", "username_value", "user_name" };
        private static string[] URL_KEYS = { "url", "origin", "origin_url", "server", "host", "domain", "signon_realm", "uri", "address" };

        public string username {
            owned get {
                foreach (string k in USER_KEYS) {
                    string? v = attributes[k];
                    if (v != null && v != "") return v;
                }
                return "";
            }
        }

        public string url {
            owned get {
                foreach (string k in URL_KEYS) {
                    string? v = attributes[k];
                    if (v != null && v != "") return v;
                }
                return "";
            }
        }

        public string notes {
            owned get { return attributes["notes"] ?? ""; }
        }

        public bool is_login {
            get { return url != "" || attributes["xdg:schema"] == Store.SCHEMA; }
        }

        public string site {
            owned get {
                string u = url;
                if (u == "") return "";
                string host = u;
                int scheme = host.index_of ("://");
                if (scheme >= 0) host = host.substring (scheme + 3);
                int slash = host.index_of_char ('/');
                if (slash >= 0) host = host.substring (0, slash);
                int colon = host.last_index_of_char (':');
                if (colon > 0 && !host.contains ("]")) host = host.substring (0, colon);
                if (host.has_prefix ("www.")) host = host.substring (4);
                return host;
            }
        }

        public string title {
            owned get {
                if (label != "") return label;
                if (site != "") return site;
                return attributes["xdg:schema"] ?? _("Untitled");
            }
        }
    }

    public class SecretCollectionInfo : Object {
        public string path = "";
        public string label = "";
        public bool locked;
        public bool is_default;
    }

    [DBus (name = "org.freedesktop.Secret.Prompt")]
    private interface PromptProxy : Object {
        public abstract void prompt (string window_id) throws GLib.Error;
        public abstract void dismiss () throws GLib.Error;
        public signal void completed (bool dismissed, GLib.Variant result);
    }

    public class Store : Object {
        public const string SCHEMA = "dev.sinty.Password";
        private const string BUS = "org.freedesktop.secrets";
        private const string SERVICE_PATH = "/org/freedesktop/secrets";
        private const string SERVICE_IFACE = "org.freedesktop.Secret.Service";
        private const string COLLECTION_IFACE = "org.freedesktop.Secret.Collection";
        private const string ITEM_IFACE = "org.freedesktop.Secret.Item";
        private const string PROPS_IFACE = "org.freedesktop.DBus.Properties";

        private DBusConnection conn;
        private string? session_path;

        public signal void changed ();

        private async Variant call (string path, string iface, string method, Variant? args, string reply_type) throws Error {
            return yield conn.call (BUS, path, iface, method, args, new VariantType (reply_type), DBusCallFlags.NONE, 120000, null);
        }

        public async void connect_service () throws Error {
            conn = yield Bus.get (BusType.SESSION);
            try {
                var r = yield call (SERVICE_PATH, SERVICE_IFACE, "OpenSession", new Variant ("(sv)", "plain", new Variant.string ("")), "(vo)");
                Variant output;
                r.get ("(vo)", out output, out session_path);
            } catch (Error e) {
                throw new SecretError.UNAVAILABLE (e.message);
            }
            watch ();
        }

        private void watch () {
            string[] members = { "CollectionCreated", "CollectionDeleted", "CollectionChanged", "ItemCreated", "ItemDeleted", "ItemChanged" };
            foreach (string m in members) {
                conn.signal_subscribe (BUS, null, m, null, null, DBusSignalFlags.NONE, () => changed ());
            }
        }

        private async Variant prop (string path, string iface, string name) throws Error {
            var r = yield call (path, PROPS_IFACE, "Get", new Variant ("(ss)", iface, name), "(v)");
            Variant v;
            r.get ("(v)", out v);
            return v;
        }

        private async void set_prop (string path, string iface, string name, Variant value) throws Error {
            yield call (path, PROPS_IFACE, "Set", new Variant ("(ssv)", iface, name, value), "()");
        }

        public async Gee.List<SecretCollectionInfo> collections () throws Error {
            var list = new Gee.ArrayList<SecretCollectionInfo> ();
            var paths = yield prop (SERVICE_PATH, SERVICE_IFACE, "Collections");
            string default_path = "";
            try {
                var r = yield call (SERVICE_PATH, SERVICE_IFACE, "ReadAlias", new Variant ("(s)", "default"), "(o)");
                r.get ("(o)", out default_path);
            } catch (Error e) {
            }
            foreach (var pv in paths) {
                string p = pv.get_string ();
                var info = new SecretCollectionInfo ();
                info.path = p;
                info.is_default = p == default_path;
                try {
                    info.label = (yield prop (p, COLLECTION_IFACE, "Label")).get_string ();
                    info.locked = (yield prop (p, COLLECTION_IFACE, "Locked")).get_boolean ();
                } catch (Error e) {
                    continue;
                }
                if (info.label == "") info.label = Path.get_basename (p);
                list.add (info);
            }
            list.sort ((a, b) => a.is_default != b.is_default ? (a.is_default ? -1 : 1) : a.label.collate (b.label));
            return list;
        }

        public async Gee.List<SecretEntry> items (SecretCollectionInfo coll) throws Error {
            var list = new Gee.ArrayList<SecretEntry> ();
            if (coll.locked) return list;
            var paths = yield prop (coll.path, COLLECTION_IFACE, "Items");
            foreach (var pv in paths) {
                string p = pv.get_string ();
                try {
                    var r = yield call (p, PROPS_IFACE, "GetAll", new Variant ("(s)", ITEM_IFACE), "(a{sv})");
                    var dict = r.get_child_value (0);
                    var e = new SecretEntry ();
                    e.path = p;
                    e.collection = coll.path;
                    var lv = dict.lookup_value ("Label", VariantType.STRING);
                    if (lv != null) e.label = lv.get_string ();
                    var tv = dict.lookup_value ("Type", VariantType.STRING);
                    if (tv != null) e.item_type = tv.get_string ();
                    var cv = dict.lookup_value ("Created", VariantType.UINT64);
                    if (cv != null) e.created = cv.get_uint64 ();
                    var mv = dict.lookup_value ("Modified", VariantType.UINT64);
                    if (mv != null) e.modified = mv.get_uint64 ();
                    var av = dict.lookup_value ("Attributes", new VariantType ("a{ss}"));
                    if (av != null) {
                        var iter = av.iterator ();
                        string k, v;
                        while (iter.next ("{ss}", out k, out v)) e.attributes[k] = v;
                    }
                    list.add (e);
                } catch (Error err) {
                }
            }
            return list;
        }

        public async string secret (SecretEntry e) throws Error {
            var r = yield call (e.path, ITEM_IFACE, "GetSecret", new Variant ("(o)", session_path), "((oayays))");
            var s = r.get_child_value (0);
            var value = s.get_child_value (2);
            unowned uint8[] data = (uint8[]) value.get_data ();
            var sb = new StringBuilder.sized (value.get_size () + 1);
            sb.append_len ((string) data, (ssize_t) value.get_size ());
            return sb.str;
        }

        private Variant secret_variant (string password) {
            var bytes = new Variant.from_bytes (new VariantType ("ay"), new Bytes (password.data), true);
            return new Variant ("(oay@ays)", session_path, new VariantBuilder (new VariantType ("ay")), bytes, "text/plain; charset=utf8");
        }

        private static Variant attrs_variant (HashTable<string, string> attrs) {
            var b = new VariantBuilder (new VariantType ("a{ss}"));
            attrs.foreach ((k, v) => b.add ("{ss}", k, v));
            return b.end ();
        }

        public async string create (SecretCollectionInfo coll, string label, HashTable<string, string> attrs, string password) throws Error {
            var props = new VariantBuilder (new VariantType ("a{sv}"));
            props.add ("{sv}", "org.freedesktop.Secret.Item.Label", new Variant.string (label));
            props.add ("{sv}", "org.freedesktop.Secret.Item.Type", new Variant.string (attrs["xdg:schema"] ?? SCHEMA));
            props.add ("{sv}", "org.freedesktop.Secret.Item.Attributes", attrs_variant (attrs));
            var args = new Variant.tuple ({ props.end (), secret_variant (password), new Variant.boolean (false) });
            var r = yield call (coll.path, COLLECTION_IFACE, "CreateItem", args, "(oo)");
            string item, prompt;
            r.get ("(oo)", out item, out prompt);
            if (prompt != "/") yield run_prompt (prompt);
            return item;
        }

        public async void update (SecretEntry e, string label, HashTable<string, string> attrs, string? password) throws Error {
            yield set_prop (e.path, ITEM_IFACE, "Label", new Variant.string (label));
            yield set_prop (e.path, ITEM_IFACE, "Attributes", attrs_variant (attrs));
            if (password != null) {
                yield call (e.path, ITEM_IFACE, "SetSecret", new Variant.tuple ({ secret_variant (password) }), "()");
            }
        }

        public async void remove (SecretEntry e) throws Error {
            var r = yield call (e.path, ITEM_IFACE, "Delete", null, "(o)");
            string prompt;
            r.get ("(o)", out prompt);
            if (prompt != "/") yield run_prompt (prompt);
        }

        public async void unlock (SecretCollectionInfo coll) throws Error {
            var r = yield call (SERVICE_PATH, SERVICE_IFACE, "Unlock", new Variant ("(ao)", new string[] { coll.path }), "(aoo)");
            string prompt;
            r.get_child (1, "o", out prompt);
            if (prompt != "/") yield run_prompt (prompt);
        }

        public async void lock (SecretCollectionInfo coll) throws Error {
            yield call (SERVICE_PATH, SERVICE_IFACE, "Lock", new Variant ("(ao)", new string[] { coll.path }), "(aoo)");
        }

        public async SecretCollectionInfo create_collection (string label) throws Error {
            var props = new VariantBuilder (new VariantType ("a{sv}"));
            props.add ("{sv}", "org.freedesktop.Secret.Collection.Label", new Variant.string (label));
            var r = yield call (SERVICE_PATH, SERVICE_IFACE, "CreateCollection", new Variant ("(a{sv}s)", props, ""), "(oo)");
            string path, prompt;
            r.get ("(oo)", out path, out prompt);
            if (prompt != "/") yield run_prompt (prompt);
            var info = new SecretCollectionInfo ();
            info.path = path;
            info.label = label;
            return info;
        }

        public async void delete_collection (SecretCollectionInfo coll) throws Error {
            yield call (coll.path, COLLECTION_IFACE, "Delete", null, "(o)");
        }

        private async void run_prompt (string path) throws Error {
            PromptProxy p = yield Bus.get_proxy (BusType.SESSION, BUS, path);
            bool dismissed = false;
            ulong id = p.completed.connect ((d, result) => {
                dismissed = d;
                run_prompt.callback ();
            });
            p.prompt ("");
            yield;
            p.disconnect (id);
            if (dismissed) throw new SecretError.DISMISSED (_("Cancelled"));
        }
    }
}
