using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Passwords {

    public class GenerateDialog : AppDialog {
        public const int LENGTH = 20;

        private string password = "";
        private Label shown;
        private Label status;
        private ToggleButton reveal;
        private Button copy;

        public GenerateDialog (Gtk.Application app) {
            base (app, false);
            set_title (_("New Password"));
            set_default_size (440, 0);

            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_top = 20;
            box.margin_bottom = 24;
            box.margin_start = 28;
            box.margin_end = 28;

            var field = new Box (Orientation.HORIZONTAL, 8);
            field.add_css_class ("pw-field");
            shown = new Label ("");
            shown.add_css_class ("pw-secret");
            shown.xalign = 0;
            shown.hexpand = true;
            shown.wrap = true;
            shown.wrap_mode = Pango.WrapMode.CHAR;
            field.append (shown);
            reveal = new ToggleButton ();
            reveal.icon_name = "view-reveal-symbolic";
            reveal.tooltip_text = _("Show Password");
            reveal.add_css_class ("flat");
            reveal.add_css_class ("circular");
            reveal.valign = Align.CENTER;
            reveal.toggled.connect (() => sync ());
            field.append (reveal);
            box.append (field);

            var hint = new Label (_("Generated with the default rules: %d characters with capital letters, numbers and symbols.").printf (LENGTH));
            hint.add_css_class ("dim-label");
            hint.wrap = true;
            hint.xalign = 0;
            box.append (hint);

            status = new Label ("");
            status.add_css_class ("caption");
            status.xalign = 0;
            status.visible = false;
            box.append (status);

            var buttons = new Box (Orientation.HORIZONTAL, 12);
            buttons.halign = Align.END;
            buttons.margin_top = 6;
            var again = new Button.with_label (_("Generate Again"));
            again.add_css_class ("pill");
            again.clicked.connect (() => generate ());
            buttons.append (again);
            copy = new Button.with_label (_("Copy"));
            copy.add_css_class ("pill");
            copy.add_css_class ("suggested-action");
            copy.clicked.connect (() => copy_password ());
            buttons.append (copy);
            box.append (buttons);
            content_box.append (box);

            default_widget = copy;
            generate ();
            map.connect (() => copy.grab_focus ());
            close_request.connect (() => {
                password = "";
                shown.label = "";
                return false;
            });
        }

        private void generate () {
            password = Generator.password (LENGTH, true, true, true);
            status.visible = false;
            sync ();
        }

        private void sync () {
            if (reveal.active) {
                shown.label = password;
                reveal.tooltip_text = _("Hide Password");
            } else {
                var dots = new StringBuilder ();
                for (int i = 0; i < password.char_count (); i++) dots.append ("•");
                shown.label = dots.str;
                reveal.tooltip_text = _("Show Password");
            }
        }

        private void copy_password () {
            var app = (PasswordsApp) application;
            app.copy_secret (get_clipboard (), password);
            status.label = _("Copied. It will be cleared from the clipboard in %u seconds.").printf (PasswordsApp.CLEAR_SECONDS);
            status.visible = true;
        }
    }
}
