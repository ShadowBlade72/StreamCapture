# StreamCapture

A shell script to automatically download a copy of a live stream.  Recommend setting this up on a cron to run every minute.

This script is setup to only record a stream if the streamer is playing the identified game listed under "game".  It will also terminate the recording if they switch away from that game.

## Requirements
You'll need the following packages to get this working.

- screen
  - `apt install screen`
- ffmpeg
  - `apt install ffmpeg`
- pipx
  - pipx is used to keep install Streamlink. Some distro's, like Ubuntu have very oudated versions if you use apt. 
  - `apt install pipx`
- jq
  - `pipx install jq`
- Streamlink
  - `pipx install streamlink`
- The following will add the items installed via pipx to your system PATH automatically.
  - `pipx ensurepath`
- curl-impersonate
  - [https://github.com/lwthiker/curl-impersonate](https://github.com/lwthiker/curl-impersonate/releases/latest)
  - If you're on linux download the package called `curl-impersonate-vXXXX.x86_64-linux-gnu.tar.gz`
    - `cd /opt/`
    - `wget [URL TO THE .tar.gz package]`
    - `tar -xvf curl-impersonate-vXXXX.x86_64-linux-gnu.tar.gz`

## Setup
You'll need to register for a developer account in order to make API calls.  These are currently utilized to pull the stream name automatically.  

- Goto: https://dev.twitch.tv/console > Register Your Application
  - Enter any name you'd like, it doesn't matter.
  - For the "OAuth Redirect URLs" you can just enter http://localhost as a placeholder.
  - Select Category "Other"
- Click Create

1. Take your ClientID and ClientSecret and place them in a file in the following format.
   - ` clientid=<CLIENTID> `
   - ` clientsecret=<CLIENTSECRET> `
2. Update the StreamCapture script with the file name and location under the "authorizationfile=<your config file>"

Now you'll need to setup StreamLink with your Twitch credentials so you can skips ads if you have Turbo or are subscribed to the streamer you're recording.
- Run the following in your browsers console: `document.cookie.split("; ").find(item=>item.startsWith("auth-token="))?.split("=")[1]`
  - Save the output in a file here: /home/USERNAME/.config/streamlink/config.twitch
  - Here is what you will enter into that file. Change `abcde...` with the auth token from your browser: `twitch-api-header=Authorization=OAuth abcdefghijklmnopqrstuvwxyz0123`
- REF: https://streamlink.github.io/cli/plugins/twitch.html
- REF: https://streamlink.github.io/cli/config.html#plugin-specific-configuration-file

## Configuration

- Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
  - twitchstreamers=(crazymango_vr aeriytheneko isthisrealvr)
  - kickstreamers=(CrazyMangoVR blu-haze)

- Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.  The "monitor...game=" is to set whether you want to only start recording when the streamer is playing that game.  If it's set to 0, it'll record them anytime they're live.
  - monitortwitchgame=1
  - monitorkickgame=1
  - game=(VRChat)

- Do you want to stop recording if your streamer switches games? You must have "monitor...game=" set to 1 for this to function.
  - stoptwitchrecord=1
  - stopkickrecord=1

- Destination path is where you'll save the recordings.  The authorization file is for your Twitch API credentials, and the configfile is where it'll save your bearer token once it authenticates.
  - destpath="/root/Recordings"
  - authorizationfile="/root/.twitchcreds.conf"
  - configfile="/root/.twitchrecord.conf"

- This is where you installed your curl-impersonate.  If you followed the directions above, it should be in /opt/.
  - curlimp="/opt/curl-impersonate/curl_chrome116"
