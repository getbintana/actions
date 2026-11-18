/* The questions only the installed tree can answer, asked from the graphical
 * host: `Video` is the GStreamer registry's sink, `PdfDocument.CanRead` is
 * poppler's build flag and `Terminal` is libvterm's. A setup that lost
 * `lib/gstreamer-1.0`, `share/poppler` or the DLL installs, launches and
 * answers false for all three.
 *
 * A throw is a line in the answer file and not a dialog waiting on a click
 * nobody will make, and the answers go to a file because a GUI executable's
 * `print` is not seen from a shell. The child with its output piped is what
 * goes through GLib's spawn helper. */
function Main() {
    Application.OnError = (e) => {
        File.Save(File.Join(Application.Directory, "answer.txt"), "error=" + e + "\n");
        Application.Quit(1);
    };
    const child = Exec.Wait([Application.Executable, "--version"]);
    File.Save(File.Join(Application.Directory, "answer.txt"),
              "exec=" + child.ExitCode + "\n" +
              "video=" + Widget.Available("Video") + "\n" +
              "pdf=" + PdfDocument.CanRead + "\n" +
              "terminal=" + Widget.Available("Terminal") + "\n");
    Application.Quit(child.ExitCode === 0 ? 0 : 1);
}
