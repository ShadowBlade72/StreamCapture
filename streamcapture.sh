#!/bin/bash
######CONFIGURATION######

#Enter your streamers seperated by spaces.  If they have a space in their name, use quotes around their name.
twitchstreamers=(crazymango_vr aeriytheneko isthisrealvr)
kickstreamers=(CrazyMangoVR blu-haze)

#Enter a list of games you want to monitor the streamers for seperated by spaces.  If there is a space in the name, use quotes around the name.
monitortwitchgame=1
monitorkickgame=0
game=(VRChat)

#Do you want to stop recording if your streamer switches games?
stoptwitchrecord=1
stopkickrecord=0

#Destination path is where you'll save the recordings.  The authorization file is for your Twitch API credentials, and teh configfile is where it'll save your bearer token once it authenticates.
destpath="/Drobo/Nyx"
authorizationfile="/root/Mango/.twitchcreds.conf"
configfile="/root/Mango/.twitchrecord.conf"

#TODO: Do we want to use the kick "API".  If so, we need curl-impersonate. Otherwise fall back to legacy mode. Having this enabled allows better episode naming.
#TODO: For now kickapi must be set to 1 and we must have curl-impersonate until I implement a legacy mode.
kickapi=1
curlimp="/opt/curl-impersonate/curl_chrome110"

######CONFIGURATION######

#Run a for loop on the streamers array so we can use multiple names to record.
fnStart(){
	for streamer in "${twitchstreamers[@]}"; do
		unset kick
		twitch=1
		fnConfig
	done
	for streamer in "${kickstreamers[@]}"; do
		unset twitch
		kick=1
		fnConfig
	done
}

#Check to see if the config file exists. If there are issues with it, the fnRequestTwitch will delete it and start over.
fnConfig(){
	if [[ ! -d $destpath/$streamer ]]; then
		mkdir $destpath/$streamer
	fi
	if [[ $twitch == 1 ]]; then
		if [[ ! -f $authorizationfile ]]; then
			echo "Config file with authorization credentials missing!"
			touch $authorizationfile
			echo "clientid=" >> $authorizationfile
			echo "clientsecret=" >> $authorizationfile
			exit
		else
			source $authorizationfile
		fi
		if [[ -f $configfile ]]; then
			source $configfile
			fnRequestTwitch
		else
			fnAccessToken
		fi
	fi
	if [[ $kick == 1 && $kickapi == 1 ]]; then
		fnRequestKick
	elif [[ $kick == 1 ]]; then
		echo "why are we here..."
		fnRequestKickLegacy
	fi
}
#Request a new access token if the one from the config file can't be loaded or is expired.
fnAccessToken(){
	if [[ -z $request || $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
		#This is doing the oauth authentication and saving the bearer token that we receive to the config file.
		access_token=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$clientid&client_secret=$clientsecret" https://id.twitch.tv/oauth2/token | jq -r '.access_token')
		echo "access_token=$access_token" > $configfile
		echo "Pulled new access token! - $access_token"
	fi
}

#Make a request to the Twitch API for the streamers information.
fnRequestTwitch(){
	request=$(curl -s -H "Client-Id: $clientid" -H "Authorization: Bearer $access_token" -X GET "https://api.twitch.tv/helix/streams?user_login=$streamer")
	if [[ $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
		#echo "Token Error: $(echo $request | jq -r '.error') ---- $access_token"
		unset access_token
		rm $configfile
		#echo "Cleared config... returning to config."
		fnConfig
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) ]] && [[ ${game[@]} =~ $(echo $request | jq -r '.data[].game_name') || $monitortwitchgame == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartTwitchRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) && ! ${game[@]} =~ $(echo $request | jq -r '.data[].game_name') && $stoptwitchrecord == 1 && $monitortwitchgame == 1 ]]; then
		#If they change game and we have stop recording set, then stop recording.
		fnStopRecord
	else
		echo "[-] $streamer is not live in $game or we're already recording."
		#echo $request
	fi
	unset twitch
}

fnRequestKick(){
	request=$($curlimp -s "https://kick.com/api/v2/channels/$streamer")
	if [[ ! $(echo $request | jq -r '.livestream.is_live // empty') ]]; then
		echo "Something happened to your streamer... they're offline, they don't exist, or the site is blocking your requests."
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) ]] && [[ ${game[@]} =~ $(echo $request | jq -r '.livestream.categories[].name') || $monitorkickgame == 0 ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartKickRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.kick.com/$streamer" | grep streamlink) && ! ${game[@]} =~ $(echo $request | jq -r '.livestream.categories[].name') && $stopkickrecord == 1 && $monitorkickgame == 1 ]]; then
		fnStopRecord
	else
		echo "[-] $streamer is not live in $game or we're already recording."
		#echo $request
	fi
	unset kick	
}

fnStartTwitchRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo $request | jq -j --arg jdate $(date +"%j") --arg ydate $(date +"%y") --arg random $RANDOM '.data[].user_login," - S",$ydate,"E",$jdate," - ",.data[].title," [",.data[].id + $random,"]"' | tr -dc '[:print:]')
	screen -dmS $streamer bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mp4\""
}

fnStartKickRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo $request | jq -j --arg jdate $(date +"%j") --arg ydate $(date +"%y") --arg random $RANDOM '.user.username," - S",$ydate,"E",$jdate," - ",.livestream.session_title," [",(.livestream.id|tostring) + $random,"]"' | tr -dc '[:print:]')
	screen -dmS $streamer bash -c "streamlink --stdout https://www.kick.com/$streamer best | ffmpeg -i - -movflags faststart -c copy \"$destpath/$streamer/$outputname.mp4\""
}

fnStopRecord(){
	#This sends a ctrl+c (SIGINT) to the screen to gracefully stop the recording.
	screen -S $streamer -X stuff $'\003'
}

fnStart
