#!/bin/bash

ACTION=$1
BASEDIR=/opt/freifunk

source /etc/environment

function update_map() {
	CWD=`pwd`
	cd $BASEDIR"/ffmap-backend"
	./mkmap.sh $BASEDIR"/data"
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/nodes.json ssh-721223-map@freifunk-aachen.de:~/new/nodes.json
	cd $CWD
} 


function update_map_merged() {
	php $BASEDIR"/ffmap-merged/nodes_merger.php"
	php $BASEDIR"/ffmap-merged/nodes_filter.php"
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/nodes-merged-aachen.json ssh-721223-map@freifunk-aachen.de:~/merged/nodes.json
}


function dump_alfred() {
	alfred-json -zr 158 > $BASEDIR"/data/alfred-nodeinfo.json"
	alfred-json -zr 159 > $BASEDIR"/data/alfred-statistics.json"
}


function dump_batadv-vis() {
	batadv-vis > $BASEDIR"/data/batadv-vis.json"
}


function update_hosts() {
	jq -r '.[]|select(.network.addresses|length > 0)|.network.addresses[] +" " +.hostname +".nodes.freifunk-aachen.de"|.' $BASEDIR/data/alfred-nodeinfo.json | grep -iE "^2a03" > $BASEDIR"/data/hosts"
	PID=$(pidof dnsmasq)
	kill -SIGHUP $PID
}


function update_stats() {
	#TODO/PERFORMANCE: Pipe jq output to nc directly
	STATSBASEDIR=$BASEDIR"/data/stats/"
	TSTAMP=$(date +%s)
	{\
		jq -r '.nodes[]|select(.clientcount !=null)|.id+".clientcount "+(.clientcount|tostring)' $BASEDIR/data/nodes.json; \
	} | while read line
	do
		echo "freifunk.nodes."$line" "$TSTAMP | nc localhost 2003
		ID=$(echo $line | grep -oP '^.*(?=.clientcount)')
		STATSDIR=$STATSBASEDIR"/nodes/"$ID
		[ -d $STATSDIR ] || /bin/mkdir -p $STATSDIR
		if [ -d $STATSDIR ]; then
			for TIME in -24h -14d -1mon -1y; do
				STEPS=24
				GROUP=1h
				case $TIME in
					-24h )
						STEPS=24; GROUP="1h"
						;;
					-14d )	STEPS=14; GROUP="1d"
						;;
					-1mon )	STEPS=30; GROUP="1d"
						;;
					-1y )	STEPS=12; GROUP="1mon"
						;;
				esac	
				#summarize(freifunk.nodes.14:cc:20:62:fa:0a.clientcount,"1h","avg")
				URL="http://localhost:8002/render?target=summarize(freifunk.nodes."$ID".clientcount,\""$GROUP"\",\"avg\")&format=json&from="$TIME
				#&maxDataPoints="$STEPS
				JSON=$STATSDIR"/clientcount_"$TIME".json"
				wget -qO "$JSON" "$URL"
			done	
		fi
	done
}

function push_stats() {
	rsync --delete -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/stats ssh-721223-map@freifunk-aachen.de:~/new/
}

case $ACTION in
    map )
	update_map
	update_stats	
        ;;
    stats )
        update_stats
        push_stats
        ;;
    * ) dump_alfred
	dump_batadv-vis
	update_map_merged
	update_hosts
	push_stats
	;;
esac

