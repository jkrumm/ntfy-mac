// Lists the owner names of the windows on screen in the logged-in GUI session, one per window, without the
// owners that are always there (a window name needs Screen Recording permission, so it is usually empty). A permission or install dialog is a window of some owner (the
// notification prompt, "Install Command Line Developer Tools", Sparkle, SecurityAgent, ...), so a script can
// tell a prompt appeared without clicking it. Run with: osascript -l JavaScript windows.js
ObjC.import("CoreGraphics");
const baseline = ["Control Center", "Dock", "Window Server", "Finder", "Wallpaper", "Spotlight", "SystemUIServer", "Notification Center"];
const windows = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(1, 0)));
const lines = [];
for (const w of windows) {
  const owner = (w.kCGWindowOwnerName || "?").trim();
  const title = (w.kCGWindowName || "").trim();
  if (baseline.includes(owner)) continue;
  const line = title ? `${owner} | ${title}` : owner;
  lines.push(line);
}
console.log(lines.join("\n"));
