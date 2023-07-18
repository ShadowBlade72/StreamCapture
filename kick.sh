#!/bin/bash
streamer=crazymangovr
destpath="/Nyx"

if [[ -z $(ps -ef | grep -v grep | grep "https://kick.com/$streamer" | grep streamlink) ]]; then
	screen -dmS $streamer bash -c "streamlink --output \"$destpath/{author}/{title} {id}.ts\" https://kick.com/$streamer best"
fi
