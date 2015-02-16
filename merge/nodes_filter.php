<?php
/////////////////////////////////////////////////////////////////////////
//  nodes_filter.php v20140817a                                        //
//  filter nodes.json to match given part of the names                 //
//  to present all nodes of a community on the ffmap-d3                //
//  by Domnique Görsch <ff@dgoersch.info>                              //
//                                                                     //
//  This work is licensed under the Creative Commons                   //
//  Attribution-NonCommercial-ShareAlike 4.0 International License.    //
//  To view a copy of this license, visit                              //
//  http://creativecommons.org/licenses/by-nc-sa/4.0/.                 //
/////////////////////////////////////////////////////////////////////////
error_reporting(E_ALL ^ E_NOTICE);                                                           // suppress notices

$src_url     = "/opt/freifunk/data/nodes-merged.json";                               // source url for nodes.json
$json_file   = "/opt/freifunk/data/nodes-merged-aachen.json";                                    // target json file
$filters_arr = array("FFAC");                                                              // array of filterstrings
$geo_filter = array(50.96,50.49,5.98,6.42);                                                // geo filter Städteregion Aachen (added by JvdH 20141219)


$src_json   = file_get_contents($src_url);                                                   // get json from source url
$src_arr    = json_decode($src_json,TRUE);                                                   // and convert to array

$ids_arr  = array();
$macs_arr = array();

foreach($src_arr['nodes'] as $node_arr) {                                                    // run through nodes
  $node = new stdClass();
  $node = json_decode(json_encode($node_arr), FALSE);

  foreach($filters_arr as $filter_str) {                                                     // run through filter strings
    if(($node->name &&                                                                        // if node has a name
       strtoupper(substr($node->name,0,strlen($filter_str))) == strtoupper($filter_str)) ||   // beginning with filter string
       ($node->geo && $node->geo[0] < $geo_filter[0] && $node->geo[0] > $geo_filter[1] && $node->geo[1] < $geo_filter[3] && $node->geo[1] > $geo_filter[2])) {   // OR inside geobox (added by JvdH 20141219)
      $ids_arr[] = $node->id;                                                                // push the id to array

      $node_macs = explode(",",$node->macs);                                                 // extract macs from node
      array_walk($node_macs,'trim_value');                                                   // trim whitespaces
      foreach($node_macs as $mac) {
        $macs_arr[] = $mac;                                                                  // and push them to array
      }
    }
  }
}

$nodes_arr = array();
$idxs_arr  = array();
$idx = 0; $hit = 0;

foreach($src_arr['nodes'] as $node_arr) {                                                    // run through nodes
  $node = new stdClass();
  $node = json_decode(json_encode($node_arr), FALSE);

  if(($node->name && $node->flags->legacy) ||                                                // if node has a name and is legacy
     strpos_array($node->id,$ids_arr) > -1 ||                                                // or its id is in ids array
     (strpos_array($node->id,$macs_arr) > -1 && $node->flags->client)) {                     // or its id is in macs array nad node is a client
    $nodes_arr[]    = $node;                                                                 // push node to array
    $idxs_arr[$idx] = $hit;                                                                  // save old position in list
    $hit++;
  }
  $idx++;
}

$links_arr = array();
foreach($src_arr['links'] as $link_arr) {                                                    // run through links
  $link = new stdClass();
  $link = json_decode(json_encode($link_arr), FALSE);

  $link->source = $idxs_arr[$link->source];                                                  // replace source with new position
  $link->target = $idxs_arr[$link->target];                                                  // replace target with new position
  if(!(is_null($link->source) || is_null($link->target))) { $links_arr[] = $link; }          // if source or target not NULL push link to array
}

$output_arr = array("nodes" => $nodes_arr,"meta" => $src_arr['meta'],"links" => $links_arr); // build output array from new nodes array, source meta array and new links array
//header('Content-type: application/json');
//echo json_encode($output_arr,JSON_UNESCAPED_SLASHES);                                        // print output as json object

file_put_contents($json_file,json_encode($output_arr,JSON_UNESCAPED_SLASHES));               // output as json object to nodes.json


// strpos() replacement with array as needles
// from http://php.net/manual/de/function.strpos.php
function strpos_array($haystack, $needles) {
  if(is_array($needles)) {
    foreach($needles as $str) {
      if(is_array($str)) {
        $pos = strpos_array($haystack, $str);
      } else {
         if ($str != "") {  // Check if needle is not empty (added by JvdH 20141219)
           $pos = strpos($haystack, $str);
         }
      }

      if($pos !== FALSE) {
        return $pos;
      }
    }
  } else {
    return strpos($haystack, $needles);
  }
}

// trim whitespaces from referenced object
// from http://php.net/manual/de/function.trim.php
function trim_value(&$value) {
  $value = trim($value);
}

?>
