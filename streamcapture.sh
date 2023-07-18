#!/bin/bash
streamers=(crazymango_vr aeriytheneko isthisrealvr)
game="VRChat"
destpath="/Nyx"
configfile="/root/.twitchrecord.conf"
authorizationfile="/root/.twitchcreds.conf"

#Run a for loop on the streamers array so we can use multiple names to record.
fnStart(){
for streamer in "${streamers[@]}"; do
	fnConfig
done
}

#Check to see if the config file exists. If there are issues with it, the fnRequest will delete it and start over.
fnConfig(){
#	echo $streamer
	if [[ ! -f $authorizationfile ]]; then
		echo "Config file with authorization credentials missing!"
		touch $authorizationfile
		echo "clientid=" >> $authorizationfile
		echo "clientsecret=" >> $authorizationfile
		exit
	else
		source $authorizationfile
	fi
	if [[ ! -d $destpath/$streamer ]]; then
		mkdir $destpath/$streamer
	fi
	if [[ -f $configfile ]]; then
		source $configfile
		fnRequest
	else
		fnAccessToken
	fi
}
#Request a new access token if the one from the config file can't be loaded or is expired.
fnAccessToken(){
	if [[ -z $request || $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
		#This is doing the oauth authentication and saving the bearer token that we receive to the config file.
		access_token=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=$clientid&client_secret=$clientsecret" https://id.twitch.tv/oauth2/token | jq -r '.access_token')
		echo "access_token=$access_token" > $configfile
		echo "Pulled new access token!"
	fi
}

#Make a request to the Twitch API for the streamers information.
fnRequest(){
	request=$(curl -s -H "Client-Id: $clientid" -H "Authorization: Bearer $access_token" -X GET "https://api.twitch.tv/helix/streams?user_login=$streamer")
	if [[ $(echo $request | jq -r '.error') != "null" || -z $access_token ]]; then
#		echo "Token Error: $(echo $request | jq -r '.error') ---- $access_token"
		unset access_token
		rm $configfile
#		echo "Cleared config... returning to config."
		fnConfig
	elif [[ -z $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) && $(echo $request | jq -r '.data[].game_name') = "$game" ]]; then
		#If we aren't already recording, and the game they're playing matches what we want to record, then start recording.
		fnStartRecord
	elif [[ -n $(ps -ef | grep -v grep | grep "https://www.twitch.tv/$streamer" | grep streamlink) && $(echo $request | jq -r '.data[].game_name') != "$game" ]]; then
		#If they change game, stop recording.
		fnStopRecord
	else
		echo "[-] $streamer is not live in $game. $request"
	fi
}

fnStartRecord(){
	# Creates an output name of "streamer_S(two digit year)E(julian date)_stream title_[streamid]"
	outputname=$(echo $request | jq -j --arg jdate $(date +"%j") --arg ydate $(date +"%y") --arg random $RANDOM '.data[].user_login," - S",$ydate,"E",$jdate," - ",.data[].title," [",.data[].id + $random,"]"' | tr -dc '[:print:]')
	screen -dmS $streamer bash -c "streamlink --stdout https://www.twitch.tv/$streamer best | ffmpeg -i - -c copy \"$destpath/$streamer/$outputname.mkv\""
}

fnStopRecord(){
	#This sends a ctrl+c (SIGINT) to the screen to gracefull stop the recording.
	screen -S $streamer -X stuff $'\003'
}

fnStart
