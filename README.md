# StreamCapture

A shell script to automatically download a copy of a live stream.  Recommend setting this up on a cron to run every minute.

This script is setup to only record a stream if the streamer is playing the identified game listed under "game".  It will also terminate the recording if they switch away from that game.

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
