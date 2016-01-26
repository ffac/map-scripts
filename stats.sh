#!/bin/bash

#Collect stats for piping them into graphite
function prepare_stats() {
	NODES_JSON_FILE=$1
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
			}|to_entries|.[] as $item|select($item.value != null)|"freifunk.nodes."+$node.key+"." + $item.key +" "+($item.value|tostring)+" '$TSTAMP'"' $NODES_JSON_FILE
	} 
}

# Finally pipe the collected stats into graphite
function update_stats() {
	NODES_JSON_FILE=$1
	prepare_stats $NODES_JSON_FILE | nc -q0 localhost 2003
}


#stats.sh /path/to/nodes.json
NODES_JSON_FILE=$1

update_stats $NODES_JSON_FILE

