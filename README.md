# StreamCapture

Setup:
You'll need to register for a developer account in order to make API calls.  These are currently utilized to pull the stream name automatically.  
Goto: https://dev.twitch.tv/console > Register Your Application
  Enter any name you'd like, it doesn't matter.  For the "OAuth Redirect URLs" you can just enter http://localhost as a placeholder.
  Select Category "Other"
  Click Create

Take your ClientID and ClientSecret and place them in a file in the following format.  Update the StreamCapture script with the file name and location under the "authorizationfile=<your config file>"
clientid=<CLIENTID>
clientsecret=<CLIENTSECRET>
