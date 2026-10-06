using Singularity.Apps.Passwords;

void test_generator () {
    for (int i = 0; i < 200; i++) {
        string p = Generator.password (16, true, true, true);
        assert (p.length == 16);
        bool lo = false, up = false, di = false, sy = false;
        for (int k = 0; k < p.length; k++) {
            if (Generator.LOWER.index_of_char (p[k]) >= 0) lo = true;
            if (Generator.UPPER.index_of_char (p[k]) >= 0) up = true;
            if (Generator.DIGITS.index_of_char (p[k]) >= 0) di = true;
            if (Generator.SYMBOLS.index_of_char (p[k]) >= 0) sy = true;
        }
        assert (lo && up && di && sy);
    }
    string only = Generator.password (8, false, false, false);
    for (int k = 0; k < only.length; k++) assert (Generator.LOWER.index_of_char (only[k]) >= 0);
    assert (Generator.password (12, true, true, true) != Generator.password (12, true, true, true));
    string phrase = Generator.passphrase (5);
    assert (phrase.split ("-").length == 5);
}

void test_meter () {
    assert (Meter.rate ("") == Strength.VERY_WEAK);
    assert (Meter.rate ("password123") == Strength.VERY_WEAK);
    assert (Meter.rate ("aaaaaaaaaaaaaaaaaaaa") <= Strength.WEAK);
    assert (Meter.rate ("Tr0ub4dor") == Strength.FAIR);
    assert (Meter.rate ("xK9#mP2$vL7@qR4!") >= Strength.STRONG);
    assert (Meter.rate ("correct-horse-battery-staple") >= Strength.STRONG);
}

void test_csv () throws SecretError {
    string chrome = "name,url,username,password,note\nGitHub,https://github.com/login,ada,\"p,a\"\"ss\",\"line1\nline2\"\n,https://x.org,bob,secret,\n";
    var recs = Csv.import (chrome);
    assert (recs.size == 2);
    assert (recs[0].name == "GitHub" && recs[0].password == "p,a\"ss" && recs[0].notes == "line1\nline2");
    assert (recs[1].name == "https://x.org" && recs[1].username == "bob");
    string firefox = "\"url\",\"username\",\"password\",\"httpRealm\"\r\n\"https://a.it\",\"u\",\"p\",\"\"\r\n";
    var ff = Csv.import (firefox);
    assert (ff.size == 1 && ff[0].url == "https://a.it" && ff[0].password == "p");
    string bw = "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n,,login,Bank,,,0,https://bank.it,me,pw,\n";
    var b = Csv.import (bw);
    assert (b.size == 1 && b[0].url == "https://bank.it" && b[0].username == "me" && b[0].password == "pw");
    assert (Csv.web_origin ("https://GitHub.com:443/login?x=1") == "https://github.com");
    assert (Csv.web_origin ("http://h.test:8080/a") == "http://h.test:8080");
    assert (Csv.web_origin ("ssh://box") == "ssh://box");
    var back = Csv.import (Csv.export (recs));
    assert (back.size == 2 && back[0].password == "p,a\"ss" && back[0].notes == "line1\nline2");
    bool threw = false;
    try {
        Csv.import ("a,b\n1,2\n");
    } catch (SecretError e) {
        threw = true;
    }
    assert (threw);
}

void test_entry () {
    var e = new SecretEntry ();
    e.attributes["origin_url"] = "https://www.example.com:443/login?x=1";
    e.attributes["username_value"] = "ada";
    assert (e.site == "example.com" && e.username == "ada" && e.is_login);
    assert (e.title == "example.com");
    e.label = "Example";
    assert (e.title == "Example");
    var app = new SecretEntry ();
    app.attributes["xdg:schema"] = "org.gnome.keyring.NetworkPassword";
    assert (!app.is_login && app.title == "org.gnome.keyring.NetworkPassword");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/passwords/generator", test_generator);
    Test.add_func ("/passwords/meter", test_meter);
    Test.add_func ("/passwords/csv", () => {
        try {
            test_csv ();
        } catch (SecretError e) {
            assert_not_reached ();
        }
    });
    Test.add_func ("/passwords/entry", test_entry);
    return Test.run ();
}
