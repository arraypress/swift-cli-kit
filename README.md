# Swift CLIKit

The shared foundation for the ArrayPress family of metadata CLIs. Every tool — `yt-fetch`, `tmdb-fetch`, `discogs-fetch` — gets the same credential store, the same output rules, the same exit codes and the same cache from this one package.

Built for tools whose main caller is an **agent or a script**, not a person. That constraint drives most of the design: output defaults to JSON when piped, errors are machine-readable and carry a repair hint, exit codes are a stable contract, and payloads are curated rather than dumped.

## Features

- 🔑 **Shared credential store** — one `0600` JSON file for every tool, namespaced by service, with environment overrides
- 🧾 **Machine-readable errors** — JSON envelope on stderr with `code`, `service`, `message` and an actionable `hint`
- 🔢 **Stable exit codes** — callers branch on `$?` instead of parsing prose
- 🖨️ **Dual-audience output** — JSON when piped, readable text on a terminal; no flag required either way
- ✂️ **Field selection** — `--fields` narrows any payload, keeping responses cheap
- 💾 **TTL disk cache** — repeat lookups served locally, off the failure path entirely
- 🛡️ **Agent safety** — other people's text fenced in random-token markers, `--read-only` from declared effects, MCP annotations, retry verdicts, a timed osascript runner
- 📁 **File plumbing** — tilde expansion, input gathering, collision-proof output names and owner-only files, shared instead of reinvented
- 🍎 **Swift 6.2** · Apple silicon · macOS 14+ · strict concurrency

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-cli-kit.git", from: "0.1.0")
```

```swift
.product(name: "CLIKit", package: "swift-cli-kit")
```

## Exit Codes

These are a public contract. Append new ones; never renumber.

| Code | Meaning | Caller should |
|------|---------|---------------|
| `0` | Success | — |
| `1` | Not found | Give up on this input |
| `2` | Usage error | Fix the arguments |
| `3` | Auth required | Run the `hint` command |
| `4` | Rate limited | Back off and retry |
| `5` | Upstream/network failure | Retry later |
| `6` | Parse failure | Upgrade the tool — the site changed. For a local tool: the file or text given can't be read, so check it; retrying won't help |

The `1` / `6` split is the one that matters most. "This video has no transcript" and "our extractor broke" both look like a missing result, but the first means stop and the second means file a bug.

```sh
yt-fetch transcript "$URL" || case $? in
  1) echo "no transcript exists" ;;
  4) sleep 60 ;;
  6) brew upgrade yt-fetch ;;
esac
```

A library's own error type is unknown to CLIKit, so `CLIError.wrapping` falls
back to `5` — retry — which is wrong for a file that isn't an image or text that
isn't a date. Libraries don't depend on CLIKit, so the tool conforms the
library's error to `CLIErrorConvertible` and names the code itself:

```swift
extension ImageForgeError: CLIErrorConvertible {
    public var cliErrorCode: CLIError.Code {
        switch self {
        case .unreadable: .parseFailure
        case .writeFailed: .upstream
        }
    }
}
```

When the tool has more to say than the library — a permission that should name
the Settings pane, a timeout that should point at the prompt causing it — it
conforms to `CLIErrorDescribing` instead and supplies the whole error, message
and hint included. The default `run()` finds either; no tool overrides `run()`
to translate errors by hand.

```swift
extension ShortcutsError: @retroactive CLIErrorDescribing {
    public var cliError: CLIError { Failure.describing(self) }
}
```

A closed pipe is part of the contract too. When the downstream reader stops
early — `yt-fetch … | head -1` — the run ends `0`, not the shell's `141`:
`CLIRunner` ignores SIGPIPE, and a broken stdout is read as "the caller has
what it wanted", not as a failure.

Argument mistakes exit `2` whichever layer catches them. ArgumentParser's own
default is `64` (BSD `sysexits.h`), so for a while a tool answered the same
class of mistake two different ways depending on whether our validation or the
parser noticed first — ``CLIRunner`` is the entry point that normalises it. Use
it instead of `@main` on the root command:

```swift
@main
enum Main {
    static func main() async { await CLIRunner.run(TMDBFetch.self) }
}
```

## Building a Tool

Declare the service, adopt `CLICommand`, and the rest is wired for you.

```swift
import ArgumentParser
import CLIKit

struct TMDBFetch: AsyncParsableCommand, ServiceProviding {

    static let service = ServiceSpec(
        id: "tmdb",
        displayName: "TMDB",
        toolName: "tmdb-fetch",
        credentials: [
            CredentialSpec(key: "api_key", label: "API key", envNames: ["TMDB_API_KEY"])
        ],
        signupURL: "https://www.themoviedb.org/settings/api"
    )

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tmdb-fetch",
            subcommands: [Movie.self, AuthCommand<TMDBFetch>.self]
        )
    }
}

struct Movie: CLICommand {
    static let serviceID = "tmdb"

    @Argument var id: Int
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        let key = try CredentialResolver(service: TMDBFetch.service).require("api_key")
        let movie = try await TMDBMetadata.movie(id, configuration: .init(apiKey: key))
        try common.emitter.emit(MoviePayload(movie, full: common.full))
    }
}
```

`AuthCommand<TMDBFetch>` provides `auth login`, `auth status` and `auth logout` from the `ServiceSpec` alone. Adopting `CLICommand` maps any thrown `CLIError` onto the right exit code and envelope.

## Discovery: `describe` and `mcp`

Add two lines to a tool's subcommand list and it becomes self-describing:

```swift
subcommands: [
    Movie.self,
    AuthCommand<TMDBFetch>.self,
    DescribeCommand<TMDBFetch>.self,
    MCPCommand<TMDBFetch>.self,
]
```

### `<tool> describe --json`

A machine-readable manifest: every invocable command, its arguments, permitted
values, defaults, output formats and exit codes.

```json
{
  "tool": "yt-fetch", "version": "0.2.0", "service": "youtube", "requiresAuth": false,
  "formats": ["json","ndjson","text","csv","markdown"],
  "exitCodes": {"1":"the resource does not exist; do not retry", "…":"…"},
  "commands": [
    { "invocation": "yt-fetch search", "path": ["search"], "summary": "Search YouTube.",
      "arguments": [
        {"kind":"positional","name":"query","required":true},
        {"kind":"option","name":"--sort","values":["relevance","date","views","rating"],"defaultValue":"relevance"}
      ] }
  ]
}
```

It is **derived from ArgumentParser's own `--experimental-dump-help`**, not
hand-maintained — a hand-written manifest is wrong the first time someone adds a
flag. Commands are flattened with a `path` array so a caller never walks a tree
to find an invocation, and `--help`/`--version` are stripped since they belong to
the parser rather than the tool.

Aggregate every tool's manifest and you have the index a directory site needs,
generated rather than curated.

### `<tool> mcp`

A Model Context Protocol server on stdio, with one MCP tool per command,
generated from the same manifest — except the protocol machinery itself:
`mcp` and `describe` stay in the manifest but are never advertised as tools,
because a server nested inside a server blocks on a stream that is already
spoken for.

```json
{ "mcpServers": { "youtube": { "command": "yt-fetch", "args": ["mcp"] } } }
```

Five decisions worth knowing:

- **It re-executes itself per call.** stdout is the protocol channel, so a
  command writing its payload there would corrupt the stream. A subprocess keeps
  them apart and preserves the exit code and stderr envelope exactly as a shell
  caller sees them. The child's stdin is the null device — the protocol stream
  stays the parent's alone.
- **…unless the tool keeps a command warm** (0.15). A tool that loads a model
  for a command pays that load on every call under re-execution. Conforming the
  root to `MCPKeepsWarm` (`static let warmCommands: Set<String> = ["make"]`) runs
  those commands in the server's own process, stdout captured through
  `Terminal.capturingStandardOutput`, so a cache the command keeps survives
  between requests. Such a command must write only through `Terminal`/`Emitter`
  and be safe to run twice in one process. `imagine` measured: SANA 15.9 s cold,
  2.9 s warm; FLUX 51.8 s cold, 25.4 s warm.
- **JSON numbers stay numbers** (0.15). `1` and `0` once reached the command as
  `true`/`false` (`--seed true`), because a JSON number also casts to `Bool`.
- **Failures come back as tool content with `isError`, not JSON-RPC errors.** The
  stderr envelope carries the `hint` that lets a model repair itself; a transport
  fault would throw that away.
- **Format flags are hidden over MCP.** The transport always wants the piped
  default, and offering `--text` invites a model to request prose it then has to
  parse.
- **Array arguments become repeated pairs.** `--field a --field b`, never
  `--field a b` — the second form binds one value under ArgumentParser's default
  `.singleValue` parsing and spills the rest into positional slots.

Credentials are resolved inside the process, so an MCP client never holds them —
unlike a server configured with keys pasted into its JSON.

One caveat worth weighing before wiring up two dozen of these: MCP tool
definitions occupy the model's context permanently, whereas a CLI costs nothing
until invoked. Register the servers you use constantly; leave the rest as CLIs.

### `<tool> mcp --channel` (0.21)

A tool that hears about things — a message arriving, a file landing — can push
them into a running Claude Code session as a
[channel](https://code.claude.com/docs/en/channels): the same server, its tools
unchanged, plus events. Conform the root to `MCPChannelProviding` and return
an `MCPChannel`:

```swift
extension IMessageCLI: MCPChannelProviding {
    static func makeChannel() throws -> any MCPChannel { MessagesChannel() }
}

struct MessagesChannel: MCPChannel {
    var instructions: String { "Messages arrive as <channel …>. Reply with the send tool." }
    func run(emit: @escaping @Sendable (MCPChannelOutput) -> Void) async throws {
        // poll, then: emit(.event(MCPChannelEvent(content: text, meta: ["chat_id": guid])))
    }
}
```

- **It starts after the handshake.** `run` is called once the client sends
  `notifications/initialized` — an event ahead of the `initialize` reply is a
  protocol violation.
- **`meta` keys must be identifiers.** Claude Code drops anything else
  silently; `MCPChannelEvent.sanitisedMeta` turns `image-path` into
  `image_path` rather than losing it.
- **`willRun(call:)` sees every tool call before it runs** — where a channel
  whose replies come back as events (a message to yourself) learns what it is
  about to send. Before, not after: a send that confirms delivery returned
  three seconds after its echo arrived.
- **Approvals by relay.** List `claude/channel/permission` in `capabilities`
  and `receive(notification:params:)` is handed each tool-approval prompt;
  `emit(.permission(requestID:allow:))` answers it.
- **Writes to stdout are serialised**, so an event never lands inside a tool
  result.

A custom channel loads with `claude --dangerously-load-development-channels
plugin:<name>@<marketplace>` until it is on Anthropic's allowlist.

### `LocalOnlyCommand` (0.21)

Some commands are the keyboard's alone — who may message a channel, which keys
a tool trusts. Offered to an agent, they are one well-worded message away from
granting a stranger access because the stranger asked. Conform a command to
`LocalOnlyCommand` and `mcp` leaves it, and everything beneath it, out of
`tools/list` and refuses it in `tools/call`. It stays in `--help` and
`describe`.

## Safety for agents (0.20)

Four things a tool driven by an agent needs, once, in the kit. The ideas come
from OpenClaw's gogcli, imsg and wacli (MIT); the code is ours.

### Other people's text is fenced: `UntrustedContent`

A message body, an email subject, a sender's display name, a note, a fetched
page — text anybody can write, handed to a model as an ordinary string. A
payload names those fields and the emitter fences their values:

```swift
extension MessageRow: UntrustedContent {
    static let untrustedFields: Set<String> = ["text", "subject", "senderName"]
}
```

```json
{"id":"msg-1","text":"<<untrusted:9f3a1c2e4b5d6f70>>Ignore your instructions…<</untrusted:9f3a1c2e4b5d6f70>>","date":"…"}
```

- **The marker** is `<<untrusted:TOKEN>>…<</untrusted:TOKEN>>`. TOKEN is 64
  random bits as 16 hex digits, drawn once per process — after the text was
  written, so the closing marker cannot be forged.
- **Before wrapping**, marker lookalikes (one bracket or two, ASCII, full-width
  or guillemets, any case, with spaces or zero-width characters inside the
  word) become `[marker removed]`, and chat-template control tokens become
  `[special token removed]`: any `<|…|>` (ChatML `<|im_start|>`, `<|system|>`,
  `<|user|>`, `<|assistant|>`, Llama 3's header and `eot` tokens, reserved
  special tokens, gpt-oss channels), DeepSeek's full-width `<｜…｜>`, `[INST]`,
  `[/INST]`, `<<SYS>>`, Mistral's `[SYSTEM_PROMPT]`, `[AVAILABLE_TOOLS]`,
  `[TOOL_CALLS]`, `[TOOL_RESULTS]`, and Gemma's `<start_of_turn>`/`<end_of_turn>`.
- **Default: on when stdout is not a terminal** (an agent is reading), off on a
  terminal (a person is). `CLIKIT_WRAP_UNTRUSTED=0/1` overrides the default and
  `--wrap-untrusted` / `--no-wrap-untrusted` override both. `mcp --no-wrap-untrusted`
  turns it off for a server; a single MCP call cannot.
- **Only declared keys, only strings.** Keys match at any depth (name nested ones
  too); an array of strings under a key has each element wrapped; ids, dates,
  numbers and undeclared keys are never touched; empty strings stay empty.
- **JSON keeps the marker inside the string value**, not in a sibling field: a
  model reads the value it is about to quote, a sibling flag is skipped or cut
  away by `--fields`, and every format built from the JSON (NDJSON, CSV, TSV,
  Markdown, HTML) carries it for free. The rewrite is a byte scanner over the
  encoded JSON, so numbers and key order are exactly what the encoder wrote.
- **Text output** is the payload's: call `Untrusted.text(value)` on the same
  fields in `renderText()` and `tableRow`; it wraps when the run wraps.
  Outside an emit — a command printing on its own — `Untrusted.text` can only
  see the terminal and the environment, not the command's flags: use
  `common.untrustedPolicy.apply(value)` there, and pass
  `untrusted: common.untrustedPolicy` to any `Emitter` built by hand. A text
  table whose payload wraps is never shortened to fit the terminal: a cut cell
  would lose its closing marker.

### `--read-only` and declared effects

Every command declares what it does:

```swift
struct ListCommand: CLICommand { static let commandEffect = CommandEffect.readOnly … }
struct SendCommand: CLICommand { static let commandEffect = CommandEffect.acting(destructive: false) … }
// MutatingCommand defaults to .acting() — destructive, not idempotent.
```

`--read-only` (every command, through `CommonOptions`) or `CLIKIT_READ_ONLY=1`
(a whole process tree, `mcp`'s children included) refuses every command that is
not `.readOnly` — **exit 2, `"retry":"not_started"`, before `execute()` runs**,
so nothing has been opened, resolved or started. The gate is in `CLICommand.run()`
and `CLIRunner`, not in the commands. A `MutatingCommand` with `--dry-run` is let
through: a plan changes nothing. So is a `ConditionallyActing` command whose
`actsThisRun` is false — `files 4821` lists, `files 4821 --save ~/x` writes;
describe and MCP still show its worst case.

The default declaration is `.undeclared`, which is handled as acting: a command
that forgot to say it only reads is refused under `--read-only` (an annoyance that
announces itself) rather than a command that sends slipping through. Each tool's
tests assert there are none:

```swift
XCTAssertEqual(CommandEffects.undeclared(in: MyTool.self), [])
```

`describe` tags each command `[reads]`, `[acts]`, `[acts, destructive]` or
`[undeclared]`, and its JSON carries `"effect":{"kind":"read_only"|"acting"|"undeclared","destructive":…,"idempotent":…}`
per command plus a `safety` block naming the flag, the variables and the marker.

### MCP annotations

`mcp` emits the hints MCP clients use to decide what needs a person's OK:
`{"readOnlyHint":true}` for a read; `readOnlyHint:false` with `destructiveHint`
and `idempotentHint` for an acting command; and the worst case (not read-only,
destructive, not idempotent) for an undeclared one. `mcp --read-only` offers only
the reads — the rest are absent from `tools/list` and unknown to `tools/call` —
and sets `CLIKIT_READ_ONLY` for every call as a backstop. The safety flags are
never part of a tool's input schema.

### Retry verdicts

A failed or uncertain action says whether doing it again is safe:

| `retry` | meaning |
|---|---|
| `not_started` | nothing was attempted — safe to retry once the cause is fixed |
| `in_flight` | started and not yet confirmed (queued) — do not retry; check later |
| `may_have_completed` | started, then the outcome was lost (timeout, crash) — check before retrying |
| `completed` | done — retrying would do it again |

`Change(…, retry: .completed)` puts it in a receipt, `CLIError(…, retry:)` in the
error envelope (`{"error":{…,"retry":"may_have_completed"}}`) and the human line
(`retry: may have completed — check before retrying`). Absent unless set: a
receipt or error that never mentions retrying encodes byte for byte as before,
and old receipts decode, so diffable plans still diff.

### `OSAScript`

The one way to run AppleScript or JXA:

```swift
let names = try OSAScript.run("tell application \"Contacts\" to return name of every group")
try OSAScript.run(sendScript, arguments: [text, chatID], timeout: 30)
```

- a hard timeout — `timeout:` if the call passes one, else
  `CLIKIT_OSASCRIPT_TIMEOUT`, else 15 s — after which the child gets SIGTERM
  and, 3 s later, SIGKILL (a limit passed in code is final; leave it out to
  let the operator's variable decide);
- stdout and stderr read together through `ChildProcess`, so a chatty script
  cannot deadlock;
- values only as `argv`, after a `--`: without it osascript parses a value that
  begins `-s` or `-e` as its own flag (measured);
- failures throw `OSAScriptError`, a `CLIErrorDescribing`: `-1743`/`-1744` →
  exit 3 with the Automation hint, `-1728`/`-1719` → 1, syntax errors → 6, a
  timeout or anything else → 5. Its `retry` is `not_started` only when the
  failure provably preceded any effect (could not launch, did not compile,
  permission refused, app not running); a timeout or runtime error says
  `may_have_completed`.

## Field selection

`--fields` narrows any payload to the named top-level keys, in whichever form
gets typed:

```sh
yt-fetch video dQw4w9WgXcQ --fields title,author     # commas
yt-fetch video dQw4w9WgXcQ --fields title author     # spaces
```

Both work. The commas matter more than they look: `--fields` parses up to the
next option, so `title,author` arrived as a single name, matched nothing, and
printed `{}` with exit 0 — a mistake wearing the costume of an answer.

Unknown names stay ignored, deliberately: a caller narrowing output across
several services should not have to know which fields each one exposes. But
when *every* name is unknown the result is empty, so that case warns on stderr
and lists what the payload actually has:

```
warning: --fields matched nothing; this payload has: author, category, channelId, …
```

stdout still carries the JSON, so a pipeline is unaffected and `--quiet`
silences the warning.

## The combined index

`agentic-index` collects every tool's `describe --json` into one document:

```sh
$ agentic-index --dir /opt/homebrew/bin --text
7 tools · 78 commands

  discogs-fetch  0.1.0  Search the Discogs catalogue and marketplace.
  domaincheck    0.1.0  Check whether domains are available to register.
  feed-fetch     0.1.0  Read RSS, Atom, RDF and JSON feeds as structured data.
  gen            0.1.0  Generate secure passwords, passphrases and UUIDs.
  hn-fetch       0.1.0  Read Hacker News listings, comment threads and search.
  readable       0.1.0  Convert web pages to clean Markdown.
  yt-fetch       0.2.0  Fetch YouTube transcripts, video, channel and comment metadata.

$ agentic-index yt-fetch readable feed-fetch -o index.json
```

A directory rendered from this is generated rather than curated — publishing a tool updates the listing, and nothing is maintained twice. It is also what an agent should fetch instead of discovering binaries one at a time: one request, every command, every argument, every exit code.

Two details worth knowing:

- **No timestamp by default.** A rebuild that changes nothing produces a byte-identical file, so CI does not churn the repository. Pass `--stamp` when you want one.
- **A broken tool is skipped, not fatal.** It is reported on stderr and the run exits `5`, so CI can decide whether a partial index is publishable. One unbuildable binary should not empty the directory.

`ToolIndex.build(from:)` is public, so the merge is usable directly and is tested independently of any binary.

## Credentials

Resolution order — **environment first, then the store**:

1. `TMDB_API_KEY` (or whatever the `ServiceSpec` declares)
2. `~/.config/arraypress/credentials.json`

Environment wins so CI, containers and one-off overrides never touch persistent state — and so the value your *library* reads through its own `Configuration.default` is the value the CLI uses.

```json
{
  "version": 1,
  "credentials": {
    "tmdb":    { "api_key": "…" },
    "discogs": { "token": "…" }
  }
}
```

One shared file is what makes many small binaries workable: `tmdb-fetch auth login` and `discogs-fetch auth login` write to the same place, and any tool can report on the others.

```sh
tmdb-fetch auth login              # prompts, echo disabled
echo "$KEY" | tmdb-fetch auth login --stdin --key api_key
tmdb-fetch auth status             # exits 3 if a required credential is missing
```

Secrets are never accepted as command-line arguments — an argument is visible in `ps` and written to shell history.

### Why not the Keychain

Keychain ACLs are bound to code signature, and a SwiftPM or Homebrew-bottled binary is **ad-hoc signed**: its identity changes on every rebuild and every version bump. An item written by one build prompts when read by the next, and `brew upgrade` re-triggers it.

That breaks worst under this project's shape, where many separate binaries share one store — `tmdb-fetch` writing an item that `discogs-fetch` reads is a cross-identity access, and therefore a GUI prompt.

The decisive problem is headless use. An agent invoking these tools from a background process, over SSH, or in CI meets either a locked keychain (`errSecInteractionNotAllowed`) or a dialog that hangs the call — worse than a clean failure.

The security gap is also narrower than it looks: the login keychain is unlocked for the whole session, so both it and a `0600` file are readable by any process running as you. Keychain's real edge is encryption at rest against offline disk access, which FileVault already covers.

`CredentialStore` is a protocol precisely so a Keychain backend can be added — reasonable if you sign with a stable Developer ID — without touching a single service CLI.

## Output

| stdout is | Default format |
|-----------|----------------|
| A pipe | Compact JSON |
| A terminal | Readable text |

Overridable with `--json`, `--text`, `--ndjson`, `--csv`, `--tsv`, `--markdown`, `--html`.

In text mode, list results render as an **aligned table** for payloads adopting `TableRenderable`:

```
ID           TITLE                                            LENGTH  VIEWS       PUBLISHED
───────────  ───────────────────────────────────────────────  ──────  ──────────  ───────────
PXC_PYeB6F8  Rick Astley - Angels On My Side (Live at The O…  3:51    45K views   1 month ago
LaOUkDBDjW8  Rick Astley - Dance (Live at The O2, London, 2…  3:54    20K views   1 month ago
```

The table fits the terminal by shrinking the **widest flexible column only** — a type declares which columns may shorten, so an identifier stays copyable while a title gives up its space. Widths are measured in display cells rather than characters, so emoji and CJK don't misalign every row after them. Adoption is opt-in: a community post or a comment is a paragraph, and forcing one into a column would truncate the only part that matters.

`--csv`, `--tsv`, `--markdown` and `--html` flatten records into a table. Columns are the **union** of keys across every record, sorted — so a record missing an optional field can't shorten the table or shift other rows into the wrong columns. Nested arrays and objects are JSON-encoded into their cell rather than dropped, because a dense cell is recoverable and a missing one isn't. CSV follows RFC 4180 (CRLF, doubled quotes); Markdown escapes pipes and folds newlines to `<br>` so one cell can't break a row; HTML is an escaped fragment that drops into a page that already has a stylesheet. Keys are sorted so output is byte-stable across runs, and piped JSON is compact — for a caller paying by the token, pretty-printing whitespace is pure cost.

**`--tsv` is the clipboard format.** A spreadsheet pastes tab-separated text straight into cells, where pasted CSV lands in one column and needs an import dialog — so `tool --tsv | pb copy` is the whole of "put this folder in Excel". TSV has no quoting convention, so a cell carrying a tab or a newline loses it rather than silently becoming two columns. Both it and CSV defuse spreadsheet formula injection: a leading `=`, `+`, `@` or `-` is prefixed with an apostrophe unless the cell is a plain number, because the clipboard route into a spreadsheet is exactly as executable as the file route.

**`DocumentTable` is not `TextTable`.** `TextTable` measures the terminal and shortens flexible columns to fit, which is right for a person reading a result and wrong for a document. A listing saved beside the files it describes, printed, or mailed has no terminal and must not lose a character to one — so `DocumentTable` pads to the widest cell, rules off the header, right-aligns the columns you mark numeric, and never truncates anything.

```swift
struct MoviePayload: Codable, TextRenderable {
    let title: String
    let year: Int

    func renderText() -> String { "\(title) (\(year))" }
}

try common.emitter.emit(payload)      // one result
try common.emitter.emitAll(payloads)  // array, or NDJSON lines
```

Diagnostics, warnings and prompts all go to **stderr**, so piping stdout into a parser never has to strip chatter.

### Cards: `--card` (0.22)

A result that can be drawn as a picture says so: with `--card` it prints a **card spec** — the JSON the
[`card`](https://github.com/arraypress/swift-card-cli) tool and [CardKit](https://github.com/arraypress/swift-card-kit)
draw — instead of the result, so an agent pipes `screentime week --card | card -o week.png` rather than re-typing the
numbers into a card by hand, which is where they get copied wrong.

```swift
import CardKit   // the tool's dependency, not CLIKit's

extension WeekPayload: CardRenderable {
    func cardJSON() throws -> Data { try JSONEncoder().encode(Card(eyebrow: "Screen Time · this week", blocks: [...])) }
}
extension DeviceRow: CardCollectionRenderable {          // a list that makes one card
    static func cardJSON(forAll values: [Any]) throws -> Data { ... }
}
```

`emit` and both `emitAll`s honour it; the spec is written as given (drawn, not read, so it is never fenced or
field-filtered). A result with no card exits 2 with `this command has no card`; `--card` beside a format flag or
`--fields` is refused. CLIKit itself knows only "some JSON", so it stays free of SwiftUI and a tool without cards
pays nothing.

### Warnings, bare values and Ctrl-C

- `common.warn("…")` writes `warning: …` to stderr and stays silent under
  `--quiet`, the flag's documented job; `Terminal.warn` is the same for code
  with no options in reach. Never write to `FileHandle.standardError` directly.
- A verb whose answer is one value (`gen password`, `ua string`) prints it
  bare even when piped, and the document only when a format is asked for by
  name: `if common.namesStructuredFormat { emit } else { print the value }`.
  `common.namedFormat` is the format a flag named, or `nil`.
- `await Interrupt.wait(timeout:)` waits for Ctrl-C, SIGTERM or the timeout,
  then keeps both ignored while the caller finalises. `Interrupt.onFirst { … }`
  runs a handler on the first Ctrl-C (a second exits 130).

## Cache

```swift
let cache = DiskCache(tool: "yt-fetch", isEnabled: !common.noCache)

let payload = try await cache.cached("transcript/\(id)/en", ttl: 7 * 24 * 3600) {
    TranscriptPayload(try await YouTubeTranscript.fetch(id))
}
```

Entries are plain files under `~/.cache/arraypress/<tool>/`, inspectable with `ls` and resettable with `rm -rf`. A corrupt, missing or unwritable entry degrades to a live fetch — the cache is never a reason for a command to fail.

Include every input that changes the result in the key, including flags that change the payload shape: a cached slim result must never be served to a caller that asked for `--full`.

## Paths, files and batch names

The filesystem plumbing every bulk tool reinvents:

```swift
let inputs = try FileSet.gather(specs.map(\.expandedPath), matching: ["yaml"])
let names  = try BatchNames.unique(for: inputs, suffix: ".pdf")

let spec   = try Files.read(path, service: "resume", hint: "pass a JSON file, or - for stdin")
let out    = try Files.ensureDirectory("~/Documents/out")
try Files.write(pdf, to: "~/Documents/out/cv.pdf")
```

`expandedPath` expands a leading `~` — a path read from a profile, a config
file or an MCP argument never met a shell. `BatchNames` derives each output
name from its input's basename and refuses to let two collide: duplicate
basenames get their parent directory as a prefix (`2024-acme.pdf` beside
`2025-acme.pdf`), and the same file given twice is a usage error rather than
two identical documents wearing different names.

`Files` does the three lines every tool writes with the same omissions: each
expands the tilde, and each fails as a `CLIError` with the right exit code — a
missing input is `1` (not found), an unwritable output is `5` — rather than a
bare Foundation message. `Files.read("-")` reads standard input, the family's
spelling for "what is piped in".

### Owner-only files

```swift
try SecureFile.write(profile, to: XDG.configHome
    .appendingPathComponent("arraypress/resume/profile.json"))
```

A saved profile is somebody's address and date of birth; the credential store
is their secrets. `SecureFile` writes both the same way: the parent directory
made at `0700`, the file created at `0600` from the first byte and then moved
into place — never written at the umask default and tightened afterwards. The
`Encodable` overload uses `JSONEncoder.readable` (sorted keys, pretty-printed),
so a file somebody opens to fix by hand is one they can, and two saves of the
same thing are the same bytes.

`XDG.configHome` and `XDG.cacheHome` are the family's one answer to where
"home" is — `$XDG_CONFIG_HOME` or `~/.config`, `$XDG_CACHE_HOME` or `~/.cache`,
a relative or empty value ignored as the specification says — so one
environment variable moves every tool's state, and a test run never writes
into a real profile to find out whether saving works.

### Models that fetch themselves

```swift
static let depth = ModelLocation(
    service: "img", names: ["img-depth-anything-v2-small-float32.aimodel"], environmentKey: "IMG_DEPTH_MODEL",
    download: "hf download arraypress/img-depth-anything --local-dir models && img depth install models/…",
    source: ModelSource(repository: "arraypress/img-depth-anything",
                        paths: ["img-depth-anything-v2-small-float32.aimodel"], licence: "Apache-2.0"))

let model = try await Self.depth.obtain(explicit: modelPath, quiet: common.quiet)
```

`obtain` looks where `resolve` looks — the path for this run, the environment
variable, Application Support — and, when the model is nowhere and the
location has a `source`, fetches it from that public Hugging Face repository
into Application Support first. Every file is checked against the hash the
repository publishes (SHA-256 for large files, the git blob hash for small
ones), and nothing is moved into place until all of it has arrived, so a
download cut off halfway leaves no half-model behind. Progress goes to stderr:
one line redrawn on a terminal, a line per tenth through a pipe. A path named
for the run is never replaced by a download, and `NO_MODEL_DOWNLOAD=1` turns
fetching off, leaving the old refusal with `download` as its hint.

A download cut off partway continues where it stopped on the next run (0.13.2).
**Gated repositories** (0.14) — ones that ask people to accept a licence first — take
`ModelSource(…, gated: true)`. They are fetched with the person's own token: `$HF_TOKEN`
(or `HUGGING_FACE_HUB_TOKEN`), then `hf auth login`'s `~/.cache/huggingface/token` (`HF_HOME`
moves it), then the fleet credential store under `huggingface`/`token` — never an argument.
No token, a rejected one (401) or an account that has not accepted the licence (403) stops
with exit 3, and the hint is the way in: the repository's URL, accept, `hf auth login`.
Hugging Face's file listing is public even for gated repositories; only the files are
refused. Measured on facebook/sam3: the token reaches the CDN redirect and a cut-off
3.4 GB file continues.

### Files at a pinned URL (0.18)

```swift
let files = [PinnedFile(url: URL(string: "https://raw.githubusercontent.com/google/fonts/<commit>/ofl/bebasneue/BebasNeue-Regular.ttf")!,
                        name: "BebasNeue-Regular.ttf", sha256: "…")]
let installed = try await PinnedDownload.obtain(files, into: folder, label: "Bebas Neue (OFL-1.1)", service: "design")
```

For assets that are not on Hugging Face: each file's SHA-256 is measured when
its URL is chosen and checked when it arrives; nothing is moved into place
until every file checks out, a cut-off file continues, and files already
installed and matching are returned with no network. `NO_MODEL_DOWNLOAD=1`
refuses the fetch (exit 1). design's open fonts are the first user.

### Compiled copies of Core AI models (0.19)

```swift
let freed = CompiledModelCache.removeModel(asset)      // the .aimodel and every compiled copy
let compiled = CompiledModelCache.bytes(of: asset)     // what the copies take, every program's
CompiledModelCache.isCompiled(asset, program: "cutout") // whether the next load is quick
```

The first load of an `.aimodel` in a program compiles it for this Mac into
`~/Library/Caches/coreai-cache/<OS build>/<program>/<main.hash>/`, one copy per
program, often as large as the model. A tool's `model remove` should take those
copies with the model; the next load compiles again.

### Staying awake

`CLIRunner` keeps the Mac out of **idle sleep** for exactly as long as a command
runs — the assertion `caffeinate -i` takes, named after the tool
(`pmset -g assertions` shows `"imagine make: working"`). The display still
sleeps and the screen still locks; nothing about the user's power settings
changes. `mcp` holds one per tool call, never while idle on stdin.

Why: on a Mac with system sleep at one minute, a job started from a background
shell — which is how agents run things — ran 5 s steps for a minute and then
crawled at 60–80 s a step through DarkWake windows. `NO_KEEP_AWAKE=1` turns it
off; `KeepAwake.during("tool: phase") { … }` holds one around any other work.

### Running other programs

`ChildProcess` (0.17) runs osascript, git, uv or anything else with both output
streams read as they fill — the one way that cannot stall:

```swift
let result = try ChildProcess.runBlocking("/usr/bin/git", ["status", "--porcelain"], directory: root)
guard result.succeeded else { throw … result.stderrText … }

// A long job: progress line by line, only the end of stderr kept, Ctrl-C/cancel stops it.
let result = try await ChildProcess.run(uv, arguments, environment: env, timeout: 3600,
                                        stdout: .none, stderr: .lastLines(12),
                                        onStdout: { line in report(line) })
```

Arguments are an array, never a shell line; stdin is `/dev/null` unless `input:` is
given (then written from its own thread); a timeout or a cancelled task sends SIGTERM,
then SIGKILL after 3 s. Lines end at `\n`, `\r\n` or a progress bar's lone `\r`.

The two traps it replaces, both found in the fleet: reading after `waitUntilExit()` (or
stdout to its end before stderr) deadlocks once the child writes a pipe buffer — 64 KB —
that nobody reads; and reading both pipes through `FileHandle.bytes` stalls, because
Foundation serves every `bytes` sequence from one serial queue (imagine train's progress
sat unread for half an hour). The tests push 1.4 MB through each stream, interleaved,
and 2 MB of stderr before any stdout.

### The small things

```swift
guard !name.isBlank else { … }             // "" and "   " alike
Terminal.writeError("wrote " + "page".counted(pages))   // 1 page, 3 pages
failures.append((input, error.cliMessage)) // a CLIError's message, else localizedDescription
```

## Releasing a Tool

Every CLI releases the same way, and the steps live here rather than in 123
copies. A tool carries two short files that never change:

- `Scripts/build-release.sh` resolves the package and hands over to
  [`Scripts/build-cli-release.sh`](Scripts/build-cli-release.sh) in its CLIKit
  checkout — build, bundle the resource `.bundle`s, strip, ad-hoc sign, check
  the arch and that `--version` matches the tag, run `--help` and
  `describe --json`, generate completions, package, print the sha256. The
  script is pinned by the tool's `Package.resolved`, like the library.
- `.github/workflows/release.yml` calls
  [`release-cli.yml`](.github/workflows/release-cli.yml) on a `v*` tag push:
  test, run the build, attach the archive to the GitHub release. This repo is
  public so private tools can call it with no organisation setting;
  `secrets: inherit` passes `DEPS_TOKEN` for tools with a private library.

What is the tool's own sits beside them, sourced by the shared script:
`Scripts/smoke.sh` for its release checks (with `status` and `expect`
provided — `expect 2 send` asserts an exit code) and `Scripts/stage.sh` for
anything extra the archive must carry. The binary's name is the package's one
executable product.

## Requirements

- macOS 14+ on Apple silicon
- Swift 6.2+ (Xcode 26) — the library builds with nonisolated-nonsending async by default

## Naming Convention

Every tool in the family is `<service>-fetch` — `yt-fetch`, `tmdb-fetch`, `reddit-fetch`, `web-fetch`. The suffix is a family marker, not a description of any one tool.

It matters because it is guessable: a caller that has met one tool can infer the binary name of the next without being told, which is worth more across two dozen binaries than precision in any single one. `-fetch` rather than `-meta` because these return content — transcripts, comments, posts — not only metadata.

The same predictability applies inside each tool: identical global flags (`--json`, `--fields`, `--full`, `--no-cache`), the same `auth` subcommand even for services needing no credentials, and the same exit codes.

## License

MIT — see [LICENSE](LICENSE).
