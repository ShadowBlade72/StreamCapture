# StreamCapture

A shell script to automatically download a copy of a live stream.  Recommend setting this up on a cron to run every minute.

This script is setup to only record a stream if the streamer is playing the identified game listed under "game".  It will also terminate the recording if they switch away from that game.

## Requirements
You'll need the following packages to get this working.

- jq
  - apt install jq
- Streamlink
  - apt install streamlink
- Streamlink Kick Plugin
  - https://github.com/nonvegan/streamlink-plugin-kick/tree/master
- curl-impersonate
  - https://github.com/lwthiker/curl-impersonate

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

## Configuration

- Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
  - twitchstreamers=(crazymango_vr aeriytheneko isthisrealvr)
  - kickstreamers=(CrazyMangoVR blu-haze)

- Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.  The "monitor...game=" is to set whether you want to only start recording when the streamer is playing that game.
  - monitortwitchgame=1
  - monitorkickgame=0
  - game=(VRChat)

- Do you want to stop recording if your streamer switches games? You must have "monitor...game=" set to 1 for this to function.
  - stoptwitchrecord=1
  - stopkickrecord=0

- Destination path is where you'll save the recordings.  The authorization file is for your Twitch API credentials, and teh configfile is where it'll save your bearer token once it authenticates.
  - destpath="/Drobo/Nyx"
  - authorizationfile="/root/Mango/.twitchcreds.conf"
  - configfile="/root/Mango/.twitchrecord.conf"

- Do we want to use the kick "API".  If so, we need curl-impersonate. Otherwise fall back to legacy mode. Having this enabled allows better episode naming.
  - kickapi=1
  - curlimp="/opt/curl-impersonate/curl_chrome110"
