# StreamCapture

StreamCapture is a Bash script for monitoring Twitch and Kick streamers and automatically recording their live streams with Streamlink. It can be setup to record only when a streamer is in one of your configured games/categories, stop when they switch away, and publish a local dashboard for quick status checks.

The script is designed to be run repeatedly, typically from cron once per minute. Active recordings run in detached `screen` sessions so the monitor command can exit while recording continues in the background.

## Features

- Monitor Twitch and Kick streamers from one script.
- Record all live streams or only streams matching configured games/categories.
- Stop an active recording when the streamer changes away from a monitored game/category.
- Store recordings by streamer under a destination directory.
- Automatically request and refresh Twitch and Kick app access tokens.
- Write status data for a local browser dashboard.
- Keep standard, error, and optional Streamlink/ffmpeg debug logs.

## Requirements

Install these command-line tools before running StreamCapture:

- `bash`
- `curl`
- `jq`
- `cmp`
- `screen`
- `ffmpeg`
- `streamlink`
- `python3`, only required when `dashboard=1`

On Debian or Ubuntu-based systems, most dependencies can be installed with:

```bash
sudo apt update
sudo apt install bash curl jq diffutils screen ffmpeg python3 pipx
```

Streamlink packages in some distro repositories may be outdated. Installing it with `pipx` is recommended:

```bash
pipx install streamlink
pipx ensurepath
```

Open a new shell after `pipx ensurepath`, then confirm Streamlink is available:

```bash
streamlink --version
```

## API Credentials

StreamCapture uses platform API credentials to check whether configured channels are live and what game/category they are streaming. It uses app/client-credentials tokens for public stream status checks.

### Twitch

1. Register a Twitch application using the Twitch developer documentation:
   https://dev.twitch.tv/docs/authentication/register-app
2. Generate or copy the application Client ID and Client Secret.
3. Twitch's client credentials flow is documented here:
   https://dev.twitch.tv/docs/authentication/getting-tokens-oauth

### Kick

1. Register a Kick app using the Kick app setup documentation:
   https://docs.kick.com/getting-started/kick-apps-setup
2. Generate or copy the app Client ID and Client Secret.
3. Kick's OAuth client credentials flow is documented here:
   https://docs.kick.com/getting-started/generating-tokens-oauth2-flow

### Credentials File

Create the file referenced by `authorizationfile` in `streamcapture.sh`. The script creates this template automatically if the file is missing, but you still need to fill in the values:

```bash
twitch_clientid=
twitch_clientsecret=
kick_clientid=
kick_clientsecret=
```

Example:

```bash
nano /path/to/.streamcreds.conf
chmod 600 /path/to/.streamcreds.conf
```

The file referenced by `configfile` is managed by StreamCapture. It stores the current access tokens and expiration timestamps:

```bash
twitch_access_token=""
twitch_access_token_expires_at=0
kick_access_token=""
kick_access_token_expires_at=0
```

You normally do not need to edit `configfile` manually.

## Configuration

Edit the configuration block at the top of `streamcapture.sh` before running the script.

### Streamers

Set the Twitch and Kick channels you want to monitor:

```bash
twitchstreamers=(streamerone streamertwo)
kickstreamers=(streamerthree streamerfour)
```

Streamer names are converted to lowercase internally for consistency with API responses.

### Games And Categories

Set the games/categories you want to record:

```bash
game=(VRChat ASMR)
```

Use quotes around names that include spaces:

```bash
game=("Just Chatting" VRChat)
```

Enable or disable game/category filtering per platform:

```bash
monitortwitchgame=1
monitorkickgame=1
```

- `1` records only when the streamer is in one of the configured `game` entries.
- `0` records whenever the streamer is live.

Control whether StreamCapture should stop an active recording when a streamer switches away from a configured game/category:

```bash
stoptwitchrecord=1
stopkickrecord=1
```

These stop settings only apply when the matching `monitor...game` setting is enabled.

### Paths

Configure where recordings, credentials, tokens, and the dashboard status filename should live:

```bash
destpath="/path/to/Recordings"
authorizationfile="/path/to/.streamcreds.conf"
configfile="/path/to/.streamtokens.conf"
status_name="status.json"
```

`destpath` must already exist and be writable. StreamCapture creates log directories and per-streamer recording directories under it as needed.

`status_name` is only the JSON filename. StreamCapture builds the absolute dashboard status path automatically from the directory containing `streamcapture.sh`, then appends `Dashboard/$status_name`.

### Dashboard

Enable or disable the local dashboard:

```bash
dashboard=1
```

- `1` starts a local dashboard server when the script runs.
- `0` disables dashboard startup.

When enabled, StreamCapture serves the dashboard from the script's `Dashboard/` directory:

```text
http://localhost:8080
```

The dashboard reads `status.json`, polls for updates, and displays live, recording, and offline states. It also includes search/filter controls, platform filters, audio alerts, grid/table views, and a local destination-path helper for copying recorded file paths.

### Logging

Configure normal logging and debug logging:

```bash
logging=2
debug=0
```

`logging` levels:

- `0`: no file logging
- `1`: standard start, stop, warning, and status logging
- `2`: standard logging plus errors
- `3`: standard, error, and verbose logging

`debug` levels:

- `0`: no Streamlink/ffmpeg debug logs
- `1`: write Streamlink and ffmpeg screen logs under `$destpath/logs/debug/`

## Usage

Make the script executable:

```bash
chmod +x streamcapture.sh
```

Run it manually:

```bash
./streamcapture.sh
```

For normal use, run it from cron every minute:

```cron
* * * * * /path/to/StreamCapture/streamcapture.sh >> /path/to/StreamCapture/cron.log 2>&1
```

Use absolute paths in cron. Cron runs with a limited environment, so make sure `streamlink`, `jq`, `ffmpeg`, and the other dependencies are available in the cron user's `PATH`.

## Recording Behavior

When StreamCapture starts a recording, it launches Streamlink in a detached `screen` session named:

```text
<streamer>-<platform>
```

Examples:

```text
streamerone-Twitch
streamerthree-Kick
```

Recordings are first written as temporary `.tmp` files:

```text
$destpath/<streamer>/<streamer> - S<year>E<julian-day> - <stream title> [<stream id><random>].tmp
```

When Streamlink exits, the script remuxes the file to MP4:

```bash
ffmpeg -y -i "$tmpfile" -c copy -movflags faststart "$output.mp4"
```

Final recordings are saved under:

```text
$destpath/<streamer>/
```

Standard logs are written to:

```text
$destpath/logs/log.txt
$destpath/logs/errlog.txt
```

Debug logs, when enabled, are written under:

```text
$destpath/logs/debug/
```

## Dashboard

The dashboard files live in `Dashboard/`. When `dashboard=1`, the script starts:

```bash
python3 -m http.server 8080
```

from the script's `Dashboard/` directory. The dashboard is then available at:

```text
http://localhost:8080
```

The script creates and updates `status.json` automatically. It includes each configured streamer, platform, live state, current game/category, stream title, viewer count, recording state, filename, and last update timestamp.

Change `status_name` if you want a different JSON filename. Keep the generated status JSON in `Dashboard/` unless you also update the dashboard/server behavior, because `dashboard.html` loads the status file from the same served directory.

## Streamlink Twitch Authentication

StreamCapture's Twitch API checks use app credentials from `authorizationfile`. Separately, Streamlink can use your Twitch account token to avoid ads when you have Twitch Turbo or are subscribed to the streamer being recorded.

Streamlink's Twitch plugin documentation is here:

https://streamlink.github.io/cli/plugins/twitch.html

Streamlink configuration details are here:

https://streamlink.github.io/cli/config.html#plugin-specific-configuration-file

This optional Streamlink configuration is separate from StreamCapture's Twitch API credentials.

## Troubleshooting

- If the script reports a missing destination path, create `destpath` first and make sure the script user can write to it.
- If API token requests fail, verify the client IDs and client secrets in `authorizationfile`.
- If the dashboard does not load, confirm `dashboard=1`, `python3` is installed, and port `8080` is available.
- If recordings do not start, test Streamlink directly with `streamlink <stream-url> best`.
- If cron runs but recordings do not start, use absolute paths and check the cron user's `PATH`.
- If a recording appears stuck, list sessions with `screen -list` and inspect the matching `<streamer>-<platform>` session.
