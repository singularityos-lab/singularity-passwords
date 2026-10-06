namespace Singularity.Apps.Passwords {

    public class Generator {
        public const string LOWER = "abcdefghijkmnopqrstuvwxyz";
        public const string UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
        public const string DIGITS = "23456789";
        public const string SYMBOLS = "!#$%&*+-=?@^_~";

        private static uint32 random_below (uint32 n) {
            uint8[] buf = new uint8[4];
            uint32 limit = uint32.MAX - (uint32.MAX % n);
            while (true) {
                read_random (buf);
                uint32 v = buf[0] | (buf[1] << 8) | (buf[2] << 16) | ((uint32) buf[3] << 24);
                if (v < limit) return v % n;
            }
        }

        private static void read_random (uint8[] buf) {
            try {
                var f = File.new_for_path ("/dev/urandom").read ();
                size_t got;
                f.read_all (buf, out got);
                f.close ();
                if (got == buf.length) return;
            } catch (Error e) {
            }
            for (int i = 0; i < buf.length; i++) buf[i] = (uint8) Random.int_range (0, 256);
        }

        public static string password (int length, bool upper, bool digits, bool symbols) {
            string[] sets = { LOWER };
            if (upper) sets += UPPER;
            if (digits) sets += DIGITS;
            if (symbols) sets += SYMBOLS;
            string all = string.joinv ("", sets);
            int n = int.max (length, sets.length);
            char[] out_c = new char[n];
            for (int i = 0; i < sets.length; i++) out_c[i] = sets[i][random_below (sets[i].length)];
            for (int i = sets.length; i < n; i++) out_c[i] = all[random_below (all.length)];
            for (int i = n - 1; i > 0; i--) {
                int j = (int) random_below (i + 1);
                char t = out_c[i];
                out_c[i] = out_c[j];
                out_c[j] = t;
            }
            var sb = new StringBuilder ();
            foreach (char c in out_c) sb.append_c (c);
            return sb.str;
        }

        public static string passphrase (int words, string separator = "-") {
            string[] list = WORDS.split (" ");
            string[] picked = {};
            for (int i = 0; i < words; i++) picked += list[random_below (list.length)];
            int at = (int) random_below (picked.length);
            picked[at] = picked[at] + random_below (10).to_string ();
            return string.joinv (separator, picked);
        }

        private const string WORDS = "acid acorn actor agent alarm album alpine amber anchor angle apple april arctic arena armor arrow atlas atom autumn avocado badge baker bamboo banjo barley basil beacon beaver berry birch bishop blanket blossom bonus border bottle brave breeze bridge bronze bubble buffalo cable cactus camera canal candle canyon captain carbon cargo carpet castle cedar cello chalk cherry chess cider cinema circus citrus clover cobalt comet copper coral cosmos cotton cradle crater crystal cupid dahlia dancer delta denim desert diamond dolphin dragon drift eagle echo eclipse ember emerald engine falcon feather fern fiddle flint fossil fountain galaxy garden garlic gazelle geyser ginger glacier globe granite gravity guitar hammer harbor harvest hazel helium heron honey horizon husky igloo indigo iris island ivory jaguar jasmine jelly jungle kayak kernel kettle kiwi koala lagoon lantern laser lemon lilac linen lizard lotus lunar magnet mango maple marble meadow melon meteor mint mirror monsoon mosaic nectar needle neon nickel noodle nutmeg oasis ocean olive onyx opal orbit orchid otter oyster paddle panda paper parrot peach pebble pepper piano pilot pixel planet plum polar pollen poppy prism puzzle quartz quill rabbit radar raven ribbon river robin rocket saddle saffron salmon sapphire satin scarlet shadow silver sketch solar sonic spark sphinx spruce squash statue storm sugar summit sunset swan tango thunder tiger timber topaz tulip tundra turbo umbrella valley vanilla velvet violet volcano waffle walnut willow winter wizard yacht yodel zebra zenith zephyr";
    }

    public enum Strength {
        VERY_WEAK,
        WEAK,
        FAIR,
        STRONG,
        VERY_STRONG;

        public string label () {
            switch (this) {
                case VERY_WEAK: return _("Very weak");
                case WEAK: return _("Weak");
                case FAIR: return _("Fair");
                case STRONG: return _("Strong");
                default: return _("Very strong");
            }
        }
    }

    public class Meter {
        private const string[] COMMON = { "password", "123456", "12345678", "qwerty", "letmein", "welcome", "admin", "iloveyou", "monkey", "dragon", "football", "abc123", "111111", "sunshine", "princess", "password1", "passw0rd", "trustno1" };

        public static double bits (string pw) {
            if (pw == "") return 0;
            int pool = 0;
            bool lo = false, up = false, di = false, sy = false, uni = false;
            unichar c;
            int i = 0;
            while (pw.get_next_char (ref i, out c)) {
                if (c >= 'a' && c <= 'z') lo = true;
                else if (c >= 'A' && c <= 'Z') up = true;
                else if (c >= '0' && c <= '9') di = true;
                else if (c < 128) sy = true;
                else uni = true;
            }
            if (lo) pool += 26;
            if (up) pool += 26;
            if (di) pool += 10;
            if (sy) pool += 33;
            if (uni) pool += 100;
            int len = pw.char_count ();
            int unique = 0;
            var seen = new Gee.HashSet<unichar> ();
            i = 0;
            while (pw.get_next_char (ref i, out c)) if (seen.add (c)) unique++;
            double effective = double.min (len, unique * 1.5 + 1);
            double b = effective * Math.log2 (double.max (pool, 2));
            string low = pw.down ();
            foreach (string w in COMMON) if (low.contains (w)) b = double.min (b, 10);
            if (pw.split ("-").length >= 4) b = double.max (b, pw.split ("-").length * 11.0);
            return b;
        }

        public static Strength rate (string pw) {
            double b = bits (pw);
            if (b < 28) return Strength.VERY_WEAK;
            if (b < 40) return Strength.WEAK;
            if (b < 60) return Strength.FAIR;
            if (b < 90) return Strength.STRONG;
            return Strength.VERY_STRONG;
        }
    }

    public class CsvRecord {
        public string name = "";
        public string url = "";
        public string username = "";
        public string password = "";
        public string notes = "";
    }

    public class Csv {
        public static Gee.List<Gee.List<string>> parse (string text) {
            var rows = new Gee.ArrayList<Gee.List<string>> ();
            var row = new Gee.ArrayList<string> ();
            var field = new StringBuilder ();
            bool q = false, any = false;
            int i = text.has_prefix ("\xef\xbb\xbf") ? 3 : 0;
            for (; i < text.length; i++) {
                char c = text[i];
                if (q) {
                    if (c == '"') {
                        if (i + 1 < text.length && text[i + 1] == '"') {
                            field.append_c ('"');
                            i++;
                        } else {
                            q = false;
                        }
                    } else {
                        field.append_c (c);
                    }
                    continue;
                }
                if (c == '"') {
                    q = true;
                    any = true;
                } else if (c == ',') {
                    row.add (field.str);
                    field.truncate ();
                    any = true;
                } else if (c == '\n' || c == '\r') {
                    if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
                    if (any || field.len > 0) {
                        row.add (field.str);
                        rows.add (row);
                    }
                    row = new Gee.ArrayList<string> ();
                    field.truncate ();
                    any = false;
                } else {
                    field.append_c (c);
                    any = true;
                }
            }
            if (any || field.len > 0) {
                row.add (field.str);
                rows.add (row);
            }
            return rows;
        }

        private static int find (Gee.List<string> header, string[] names) {
            for (int i = 0; i < header.size; i++) {
                string h = header[i].strip ().down ();
                foreach (string n in names) if (h == n) return i;
            }
            return -1;
        }

        public static Gee.List<CsvRecord> import (string text) throws SecretError {
            var rows = parse (text);
            if (rows.size == 0) return new Gee.ArrayList<CsvRecord> ();
            var header = rows[0];
            int name = find (header, { "name", "title", "label" });
            int url = find (header, { "url", "login_uri", "website", "origin", "hostname" });
            int user = find (header, { "username", "login_username", "user", "login", "email" });
            int pass = find (header, { "password", "login_password" });
            int note = find (header, { "note", "notes", "extra", "comment" });
            if (pass < 0) throw new SecretError.FAILED (_("The file has no password column"));
            var out_l = new Gee.ArrayList<CsvRecord> ();
            for (int r = 1; r < rows.size; r++) {
                var row = rows[r];
                var rec = new CsvRecord ();
                if (name >= 0 && name < row.size) rec.name = row[name];
                if (url >= 0 && url < row.size) rec.url = row[url];
                if (user >= 0 && user < row.size) rec.username = row[user];
                if (pass < row.size) rec.password = row[pass];
                if (note >= 0 && note < row.size) rec.notes = row[note];
                if (rec.password == "" && rec.username == "") continue;
                if (rec.name == "") rec.name = rec.url;
                out_l.add (rec);
            }
            return out_l;
        }

        public static string web_origin (string url) {
            try {
                var u = Uri.parse (url.strip (), UriFlags.NONE);
                string scheme = (u.get_scheme () ?? "").down ();
                string? host = u.get_host ();
                if ((scheme != "https" && scheme != "http") || host == null || host == "") return url;
                if (host.contains (":")) host = "[" + host + "]";
                int port = u.get_port ();
                bool default_port = port < 0 || (scheme == "https" && port == 443) || (scheme == "http" && port == 80);
                return default_port ? "%s://%s".printf (scheme, host.down ()) : "%s://%s:%d".printf (scheme, host.down (), port);
            } catch (UriError e) {
                return url;
            }
        }

        private static string q (string s) {
            if (s.contains (",") || s.contains ("\"") || s.contains ("\n") || s.contains ("\r")) return "\"" + s.replace ("\"", "\"\"") + "\"";
            return s;
        }

        public static string export (Gee.List<CsvRecord> records) {
            var sb = new StringBuilder ("name,url,username,password,note\n");
            foreach (var r in records) sb.append ("%s,%s,%s,%s,%s\n".printf (q (r.name), q (r.url), q (r.username), q (r.password), q (r.notes)));
            return sb.str;
        }
    }
}
