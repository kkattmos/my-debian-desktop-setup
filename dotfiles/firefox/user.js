// Gooey (match the Ptyxis terminal): load chrome/userChrome.css and chrome/userContent.css,
// and allow a see-through window so Blur my Shell can blur behind it.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("widget.transparent-windows", true);
user_pref("browser.tabs.allow_transparent_browser", true);
