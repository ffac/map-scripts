<?php
/////////////////////////////////////////////////////////////////////////
//  nodes_merge.php v20140819a                                         //
//  merge several nodes.json to present all on one ffmap-d3            //
//  by Domnique Görsch <ff@dgoersch.info>                              //
//                                                                     //
//  This work is licensed under the Creative Commons                   //
//  Attribution-NonCommercial-ShareAlike 4.0 International License.    //
//  To view a copy of this license, visit                              //
//  http://creativecommons.org/licenses/by-nc-sa/4.0/.                 //
/////////////////////////////////////////////////////////////////////////
error_reporting(E_ALL ^ E_NOTICE);                                                           // suppress notices

$src_urls    = array(
               "http://ffmap.freifunk-rheinland.net/nodes.json",
	       "/opt/freifunk/data/nodes.json",
               );                                                                            // source urls

$json_file  = "/opt/freifunk/data/nodes-merged.json";

$nodes        = array();
$links        = array();
$offsets_arr  = array(0);
$offset       = 0;
$json_counter = 0;

foreach($src_urls as $src_index => $src_url) {                                                             // from each url
  $src_json   = file_get_contents($src_url);                                                 // get nodes.json
  $src_arr    = json_decode($src_json,TRUE);                                                 // and convert to url

  foreach($src_arr['nodes'] as $node_arr) {                                                  // run through nodes
    $node = new stdClass();
    $node = json_decode(json_encode($node_arr), FALSE);
    $node->src_index = $src_index;
    $nodes_arr[] = $node;                                                                    // push node to nodes array
    $offset++;                                                                               // and count each node
  }
  $offsets_arr[] = $offset;                                                                  // save last offset after each nodes.json

  foreach($src_arr['links'] as $link_arr) {                                                  // run through links
    $link = new stdClass();
    $link = json_decode(json_encode($link_arr), FALSE);

    $link->source = $link->source + $offsets_arr[$json_counter];                             // add offset to source
    $link->target = $link->target + $offsets_arr[$json_counter];                             // add offset to target
    $links_arr[] = $link;                                                                    // and push link to links array
  }

  $json_counter++;
}

$counts = array();
foreach($links_arr as $lkey=>$link) {                                                  // run through links
  if ($link->type == 'client') {
    $nodes_arr[$link->source]->clientcount++;
    $nodes_arr[$link->target]->clientcount++;
    unset($links_arr[$lkey]);
  }
}

foreach ($nodes_arr as $nkey=>$node) {
  if ($node->flags->client) {
    $nodes_arr[$nkey] = null;
  }
}

$meta_arr   = array("timestamp" => date("Y-m-d\TH:i:s"));                                    // create timestamp and push it to meta array
$output_arr = array("nodes" => $nodes_arr,"meta" => $meta_arr,"links" => $links_arr);        // build output array from new nodes array, meta array and new links array

file_put_contents($json_file,json_encode($output_arr,JSON_UNESCAPED_SLASHES));               // output as json object to nodes.json
?>
