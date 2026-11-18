/* A `main` project never initialises GTK: what lets it run with no display.
 * The arithmetic is the vendored QuickJS patch answering from the package. */
function Main() {
    const answer = new Decimal("10") / 3 * 3;
    print("smoke: " + answer);
    Application.Quit(answer.toString() === "10" ? 0 : 1);
}
