#!/bin/bash

ACTION=$1
BASEDIR=/opt/freifunk

source /etc/environment

# Create nodes.json for meshviewer
function update_map() {
   	$BASEDIR"/ffmap-backend/backend.py" -p 7 -d $BASEDIR"/data" -a $BASEDIR"/aliases/supernodes.json" -V $(jq -r '.[]|.network.mesh.bat0.interfaces.tunnel|.[]' $BASEDIR"/aliases/supernodes.json"|xargs)
	mv $BASEDIR"/data/nodes.json" $BASEDIR"/data/nodes-unfiltered.json"
	jq -c '.nodes = (.nodes | with_entries(del(.value.nodeinfo.owner, .value.statistics.traffic)))' < $BASEDIR"/data/nodes-unfiltered.json" > $BASEDIR"/data/nodes.json"
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR"/data/nodes.json" $BASEDIR"/data/graph.json" ssh-721223-map@freifunk-aachen.de:~/v2/data/

	# Create nodes.json for ffmap-d3
	CWD=`pwd`
	cd $BASEDIR"/ffmap-backend-legacy"
	./mkmap.sh $BASEDIR"/data/legacy"
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/legacy/nodes.json ssh-721223-map@freifunk-aachen.de:~/nodes.json.tmp
	ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen ssh-721223-map@freifunk-aachen.de "mv ~/nodes.json.tmp ~/nodes.json"
	cd $CWD
}


# Dump alfred data
function dump_alfred() {
	# Save node info
	alfred-json -zr 158 > $BASEDIR"/data/alfred-nodeinfo.json"

	# Save node statistics
	alfred-json -zr 159 > $BASEDIR"/data/alfred-statistics.json"

	# Merge node info and stats
	jq -s '[. as $all|$all[0]|to_entries[] as $node|{ key: $node.key, value: ($node.value + $all[1][$node.key]) }]|from_entries|.'\
		 $BASEDIR/data/alfred-nodeinfo.json $BASEDIR/data/alfred-statistics.json > $BASEDIR/data/alfred-merged.json

	# Filter merged result for public usage
	jq '[.|to_entries[] as $node|{ key: $node.key, value: {
			hostname: $node.value.hostname,
			software: $node.value.software,
			hardware: $node.value.hardware,
			memory: {
				free: $node.value.memory.free
			},
			loadavg: $node.value.loadavg,
			traffic: {
				rx: {bytes : $node.value.traffic.rx.bytes},
				tx: {bytes : $node.value.traffic.tx.bytes}
			},
			uptime: $node.value.uptime,
			network: {
				addresses: $node.value.network.addresses
			}
		}}]|from_entries|.' $BASEDIR/data/alfred-merged.json > $BASEDIR/data/alfred-public.json
}


# Save vis data
function dump_batadv-vis() {
	batadv-vis > $BASEDIR"/data/batadv-vis.json"
}


# Create host file for dnsmasq to allow name resolution of nodes
function update_hosts() {
	jq -r '.[]|select(.network.addresses|length > 0)|.network.addresses[] +" " +.hostname +".nodes.ffac"|.' $BASEDIR/data/alfred-nodeinfo.json | grep -iE "^2a03" > $BASEDIR"/data/hosts"
	PID=$(pidof dnsmasq)
	kill -SIGHUP $PID
}


# Collect stats for piping them into graphite
function prepare_stats() {
	TSTAMP=$(date +%s)
	{\
		#Alfred stats
		jq -r '.["nodes"]|to_entries|.[] as $node|{
				loadavg: $node.value.statistics.loadavg,
				uptime: $node.value.statistics.uptime,
				"traffic.forward.bytes": $node.value.statistics.traffic.forward.bytes,
				"traffic.mgmt_rx.bytes": $node.value.statistics.traffic.mgmt_rx.bytes,
				"traffic.rx.bytes": $node.value.statistics.traffic.rx.bytes,
				"traffic.mgmt_tx.bytes": $node.value.statistics.traffic.mgmt_tx.bytes,
				"traffic.tx.bytes": $node.value.statistics.traffic.tx.bytes,
				"rootfs_usage": $node.value.statistics.rootfs_usage,
				"memory.buffers": $node.value.statistics.memory.buffers,
				"memory.total": $node.value.statistics.memory.total,
				"memory.cached": $node.value.statistics.memory.cached,
				"memory.free": $node.value.statistics.memory.free,
				"rootfs_usage": $node.value.statistics.rootfs_usage,
				"online" : (if $node.value.flags.online != null then (if $node.value.flags.online == true then "1" else "0" end) else null end),
				"clientcount" : ($node.value.statistics.clients // 0)
			}|to_entries|.[] as $item|select($item.value != null)|"freifunk.nodes."+$node.key+"." + $item.key +" "+($item.value|tostring)+" '$TSTAMP'"' $BASEDIR/data/nodes-unfiltered.json
	} | sed -r 's/\.nodes\.([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})\./\.nodes\.\1:\2:\3:\4:\5:\6\./ig'
}

# Finally pipe the collected stats into graphite
function update_stats() {
	prepare_stats | nc -q0 localhost 2003
} 


# Global domain stats
function prepare_stats_domains() {
	{\
		TSTAMP=$(date +%s)
		wget -qO- http://map.freifunk-ruhrgebiet.de/counts/?json| \
		jq -r '.domaenen+{global: .global}|to_entries as $els|$els[] as $el|{
			"ratio": $el.value.ratio[0],
			"server.max": $el.value.server.max,
			"server.min": $el.value.server.min,
			"tunnel": $el.value.tunnel[0],
			"clients": $el.value.clients[0],
			"nodes.offline" : $el.value.nodes.offline,
			"nodes.online": $el.value.nodes.online
		}|to_entries|.[]|"freifunk.statistics.domains."+$el.key+"."+.key + " " +(.value|tostring)+" '$TSTAMP'"'
	}
}


# Pipe the collected domain stats into graphite
function update_stats_domains() {
	prepare_stats_domains | nc -q0 localhost 2003
}


# Create json files containing stat data for chart views
function dump_stats() {
        STATSBASEDIR=$BASEDIR"/data/stats/"
        GRAPHITEBASEDIR=/opt/graphite
        declare -A TIMESGROUPBY=(
                ["4h"]="15min"
                ["24h"]="1h"
                ["14d"]="1d"
                ["1mon"]="1d"
                ["1y"]="1mon"
        )
        declare -A METRICSAGGREGATION=(
                ["clientcount"]="max"
                ["loadavg"]="avg"
                ["uptime"]="last"
		["traffic.rx.bytes"]="sum"
		["traffic.tx.bytes"]="sum"
        )
        for ID in `ls $GRAPHITEBASEDIR/storage/whisper/freifunk/nodes/`; do
                STATSDIR=$STATSBASEDIR"/nodes/"$ID
                [ -d $STATSDIR ] || /bin/mkdir -p $STATSDIR
                if [ -d $STATSDIR ]; then
                        JSON=$STATSDIR"/statistics.json"
                        {\
                        for TIME in "${!TIMESGROUPBY[@]}"; do
                                GROUP=${TIMESGROUPBY["$TIME"]}

                                GURL="http://localhost:8002/render?format=json&from=-"$TIME
                                for METRIC in "${!METRICSAGGREGATION[@]}"; do
                                        AGG=${METRICSAGGREGATION["$METRIC"]}
                                        GURL+="&target=alias(summarize(freifunk.nodes."$ID"."$METRIC",\""$GROUP"\",\""$AGG"\"),\""$METRIC"_"$TIME"\")"
                                done
                                wget -qO- "$GURL"
                        done
                        } | jq -s '.' > "$JSON"
                fi
        done
}


# Push stats to the web server
function push_stats() {
	rsync --delete -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/stats $BASEDIR/data/alfred-public.json ssh-721223-map@freifunk-aachen.de:~/
}


MINUTE=$(date +%M)
EVERY=15

if [ "$ACTION" != "" ]; then

	case $ACTION in
		stats)  
			update_stats
			update_stats_domains
			dump_stats
			push_stats
			;;
		stats-update)
			update_stats
                        update_stats_domains
			;;
		stats-push)
			push_stats
			;;
		dns)
			update_hosts
			;;
		map)	
			update_map
			;;
		*)	
			;;
	esac

else
	# Every call
	dump_alfred
        dump_batadv-vis
        update_map
        update_stats
	if [ $(($MINUTE % $EVERY)) -eq 0 ]; then
		# Every $EVERY minutes
		update_stats_domains
		update_hosts
		dump_stats
		push_stats
	fi
fi
