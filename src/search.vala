namespace Singularity.Apps.Passwords {

    public class PasswordSearch : Singularity.SearchProviderService {
        public const uint CLEAR_SECONDS = 30;
        private const string LOCKED_ID = "locked";
        private const string[] PREFIXES = { "pw", "password", "passwords" };
        private const int64 CACHE_USEC = 20 * TimeSpan.SECOND;

        private weak PasswordsApp app;
        private Store? store;
        private Gee.List<SecretEntry> cache = new Gee.ArrayList<SecretEntry> ();
        private bool cache_locked;
        private int64 cached_at;

        public PasswordSearch (PasswordsApp app) {
            this.app = app;
        }

        private static bool wanted (string[] terms, out string[] words) {
            string[] found = {};
            words = found;
            if (terms.length == 0) return false;
            bool prefixed = false;
            foreach (unowned string p in PREFIXES) if (terms[0].down () == p) prefixed = true;
            if (!prefixed) return false;
            for (int i = 1; i < terms.length; i++) found += terms[i].casefold ();
            words = found;
            return true;
        }

        private static bool matches (SecretEntry e, string[] words) {
            string hay = (e.title + " " + e.site + " " + e.url + " " + e.username).casefold ();
            foreach (string w in words) if (!hay.contains (w)) return false;
            return true;
        }

        private async bool ready () {
            if (store != null) return true;
            var s = new Store ();
            try {
                yield s.connect_service ();
            } catch (Error e) {
                return false;
            }
            s.changed.connect (() => cached_at = 0);
            store = s;
            return true;
        }

        private async void refresh (bool force) {
            if (!force && cached_at != 0 && get_monotonic_time () - cached_at < CACHE_USEC) return;
            var list = new Gee.ArrayList<SecretEntry> ();
            bool locked = false;
            if (yield ready ()) {
                try {
                    foreach (var coll in yield store.collections ()) {
                        if (coll.locked) {
                            locked = true;
                            continue;
                        }
                        foreach (var e in yield store.items (coll)) if (e.is_login) list.add (e);
                    }
                } catch (Error e) {
                    locked = true;
                }
            }
            list.sort ((a, b) => a.title.collate (b.title));
            cache = list;
            cache_locked = locked;
            cached_at = get_monotonic_time ();
        }

        private SecretEntry? find (string path) {
            foreach (var e in cache) if (e.path == path) return e;
            return null;
        }

        private async bool still_unlocked (SecretEntry e) {
            if (!(yield ready ())) return false;
            try {
                foreach (var coll in yield store.collections ()) {
                    if (coll.path == e.collection) return !coll.locked;
                }
            } catch (Error err) {
            }
            return false;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            string[] words;
            if (!wanted (terms, out words)) return {};
            yield refresh (false);
            string[] ids = {};
            foreach (var e in cache) if (matches (e, words)) ids += e.path;
            if (ids.length == 0 && cache_locked) return { LOCKED_ID };
            return ids;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                if (id == LOCKED_ID) {
                    var meta = new Singularity.SearchResultMeta (id, _("Passwords Are Locked"));
                    meta.description = _("Open Passwords to unlock the keyring");
                    metas += meta;
                    continue;
                }
                var e = find (id);
                if (e == null) {
                    yield refresh (true);
                    e = find (id);
                }
                if (e == null) continue;
                var meta = new Singularity.SearchResultMeta (id, e.title);
                string user = e.username;
                string site = e.site;
                if (user != "" && site != "" && site != e.title) meta.description = "%s, %s".printf (user, site);
                else if (user != "") meta.description = user;
                else if (site != "") meta.description = site;
                if (user != "") meta.add_action ("copy-username", _("Copy Username"), "avatar-default-symbolic");
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            if (id == LOCKED_ID) {
                app.activate ();
                return null;
            }
            var e = find (id);
            if (e == null) {
                yield refresh (true);
                e = find (id);
            }
            if (e == null || !(yield still_unlocked (e))) {
                app.activate ();
                return null;
            }
            string password;
            try {
                password = yield store.secret (e);
            } catch (Error err) {
                app.activate ();
                return null;
            }
            if (password == "") return null;
            return Singularity.SearchActivationReply.copy (password, true, CLEAR_SECONDS);
        }

        public override async Singularity.SearchActivationReply? activate_action (string id, string action_id, string[] terms, uint32 timestamp) throws Error {
            if (action_id != "copy-username") return null;
            var e = find (id);
            if (e == null) {
                yield refresh (true);
                e = find (id);
            }
            if (e == null || e.username == "") return null;
            return Singularity.SearchActivationReply.copy (e.username);
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.activate ();
        }
    }
}
