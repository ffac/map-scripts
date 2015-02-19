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
	php $BASEDIR"/scripts/merge/nodes_merger.php"
	php $BASEDIR"/scripts/merge/nodes_filter.php"
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


function prepare_stats() {
	TSTAMP=$(date +%s)
	{\
		#Alfred stats
		jq -r '.|to_entries|.[] as $node|{
				loadavg: $node.value.loadavg,
				uptime: $node.value.uptima,
				"traffic.forward.bytes": $node.value.traffic.forward.bytes,
				"traffic.mgmt_rx.bytes": $node.value.traffic.mgmt_rx.bytes,
				"traffic.rx.bytes": $node.value.traffic.rx.bytes,
				"traffic.mgmt_tx.bytes": $node.value.traffic.mgmt_tx.bytes,
				"traffic.tx.bytes": $node.value.traffic.tx.bytes,
				"rootfs_usage": $node.value.rootfs_usage,
				"memory.buffers": $node.value.memory.buffers,
				"memory.total": $node.value.memory.total,
				"memory.cached": $node.value.memory.cached,
				"memory.free": $node.value.memory.free,
				"rootfs_usage": $node.value.rootfs_usage
			}|to_entries|.[] as $item|select($item.value != null)|"freifunk.nodes."+$node.key+"." + $item.key +" "+($item.value|tostring)+" '$TSTAMP'"' $BASEDIR/data/alfred-statistics.json


		#Nodes stats
		jq -r '.nodes[] as $node|{
				online: (if $node.flags.online != null then (if $node.flags.online == true then "1" else "0" end) else null end),
				clientcount: $node.clientcount
			}|to_entries|.[] as $item|select($item.value != null)|"freifunk.nodes."+$node.id+"." + $item.key +" "+($item.value|tostring)+" '$TSTAMP'"' $BASEDIR/data/nodes.json

	}
}

function update_stats() {
	prepare_stats | nc -q0 localhost 2003
} 

function test_stats() {
	prepare_stats
}

function dump_stats() {
	STATSBASEDIR=$BASEDIR"/data/stats/"
	GRAPHITEBASEDIR=/opt/graphite
	for ID in `ls $GRAPHITEBASEDIR/storage/whisper/freifunk/nodes/`; do
		STATSDIR=$STATSBASEDIR"/nodes/"$ID
		[ -d $STATSDIR ] || /bin/mkdir -p $STATSDIR
		if [ -d $STATSDIR ]; then
			for TIME in -4h -24h -14d -1mon -1y; do
				GROUP=1h
				case $TIME in
					-4h )	GROUP="15min"
						;;
					-24h )
						GROUP="1h"
						;;
					-14d )	GROUP="1d"
						;;
					-1mon )	GROUP="1d"
						;;
					-1y )	GROUP="1mon"
						;;
				esac
				GURL="http://localhost:8002/render?format=json&from="$TIME
				GURL+="&target=alias(summarize(freifunk.nodes."$ID".clientcount,\""$GROUP"\",\"avg\"),\"clientcount\")"
				GURL+="&target=alias(summarize(freifunk.nodes."$ID".loadavg,\""$GROUP"\",\"avg\"),\"loadavg\")"
				GURL+="&target=alias(summarize(freifunk.nodes."$ID".uptime,\""$GROUP"\",\"last\"),\"uptime\")"

				JSON=$STATSDIR"/statistics_"$TIME".json"
                                wget -qO "$JSON" "$GURL"

				URL="http://localhost:8002/render?target=summarize(freifunk.nodes."$ID".clientcount,\""$GROUP"\",\"avg\")&format=json&from="$TIME
				JSON=$STATSDIR"/clientcount_"$TIME".json"
				wget -qO "$JSON" "$URL"
			done	
		fi
	done
}

function push_stats() {
	rsync --delete -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/stats ssh-721223-map@freifunk-aachen.de:~/new/
}

MINUTE=$(date +%M)
EVERY=5

if [ "$ACTION" != "" ]; then

	case $ACTION in
		stats)  
			update_stats
			dump_stats
			push_stats
			;;
		stats-test)
			test_stats
			;;
		map)	
			update_map
			;;
		map-merged)
			update_map_merged
			;;
		*)	
			;;
	esac

else
	# Every call
	dump_alfred
        dump_batadv-vis
        update_map
        update_map_merged
        update_stats

	if [ $(($MINUTE % $EVERY)) -eq 0 ]; then
		# Every $EVERY minutes
		update_hosts
		dump_stats
		push_stats
	fi
fi
