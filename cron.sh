#!/bin/bash

ACTION=$1
BASEDIR=/opt/freifunk

source /etc/environment

# Helper function to remove geo informations from given nodes
function filter_geo() {
	SRC=$1
	DEST=$2
	jq -r 'with_entries(.value |= [ .[] as $el| if
		$el.id == "14:cc:20:31:20:84" #ffdn-Hambach_Mobil (NORDPOL)
		or $el.id == "14:cc:20:31:20:84" #ffdn-Hambach_Mobil (NORDPOL)
#		or $el.id == "14:cc:20:62:f8:e6" #ffac-ppnv-dr-06-orinoco-04 (Duisburg)
#		or $el.id == "14:cc:20:62:f8:c0" #ffac-ppnv-dr-06-orinoco-01 (Duisburg)
#		or $el.id == "14:cc:20:62:f8:5c" #ffac-ppnv-dr-06-orinoco-03 (Duisburg)
#		or $el.id == "14:cc:20:62:f0:f4" #ffac-ppnv-dr-06-orinoco-06 (Duisburg)
#		or $el.id == "14:cc:20:62:f6:30" #ffac-ppnv-dr-06-orinoco-02 (Duisburg)
	then $el|. + { geo: null } else $el end ] )' $SRC > $DEST
}


# Create nodes.json for ffmap-d3
function update_map() {
	CWD=`pwd`
	cd $BASEDIR"/ffmap-backend"
	./mkmap.sh $BASEDIR"/data"
	filter_geo $BASEDIR/data/nodes.json $BASEDIR/data/nodes.json.tmp
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/nodes.json.tmp ssh-721223-map@freifunk-aachen.de:~/new/nodes.json.tmp
	ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen ssh-721223-map@freifunk-aachen.de "mv ~/new/nodes.json.tmp ~/new/nodes.json"
	rm $BASEDIR/data/nodes.json.tmp
	cd $CWD
} 


# Obsolete: Merge nodes from Rheinufer with nodes from Aachen
function update_map_merged() {
	php $BASEDIR"/scripts/merge/nodes_merger.php"
	php $BASEDIR"/scripts/merge/nodes_filter.php"
	filter_geo $BASEDIR/data/nodes-merged-aachen.json $BASEDIR/data/nodes-merged-aachen.json.tmp
	rsync -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/nodes-merged-aachen.json.tmp ssh-721223-map@freifunk-aachen.de:~/merged/nodes.json.tmp
	ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen ssh-721223-map@freifunk-aachen.de "mv ~/merged/nodes.json.tmp ~/merged/nodes.json"
	rm $BASEDIR/data/nodes-merged-aachen.json.tmp
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
	jq -r '.[]|select(.network.addresses|length > 0)|.network.addresses[] +" " +.hostname +".node.freifunk-aachen.de"|.' $BASEDIR/data/alfred-nodeinfo.json | grep -iE "^2a03" > $BASEDIR"/data/hosts"
	PID=$(pidof dnsmasq)
	kill -SIGHUP $PID
}


# Collect stats for piping them into graphite
function prepare_stats() {
	TSTAMP=$(date +%s)
	{\
		#Alfred stats
		jq -r '.|to_entries|.[] as $node|{
				loadavg: $node.value.loadavg,
				uptime: $node.value.uptime,
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


# For testing purposes
function test_stats() {
	prepare_stats
	prepare_stats_domains
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
	rsync --delete -q -avz -e "ssh -i $BASEDIR/keys/ssh-721223-map_freifunk_aachen" $BASEDIR/data/stats $BASEDIR/data/alfred-public.json ssh-721223-map@freifunk-aachen.de:~/new/
}


MINUTE=$(date +%M)
EVERY=5

if [ "$ACTION" != "" ]; then

	case $ACTION in
		stats)  
			update_stats
			update_stats_domains
			dump_stats
			push_stats
			;;
		stats-test)
			test_stats
			;;
		dns)
			update_hosts
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
		update_stats_domains
		update_hosts
		dump_stats
		push_stats
	fi
fi
