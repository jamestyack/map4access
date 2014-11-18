#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'pp'
require 'CSV'
require 'open-uri'

$mainEntrance = {}
$mainEntrance['yes_wide_with_good_ramp'] = "#1a9850"
$mainEntrance['limited_tight_door_andor_subpar_ramp'] = "#91cf60"
$mainEntrance['limited_tight_door'] = "#d9ef8b"
$mainEntrance['limited_one_step_port_ramp'] = "#fee08b"
$mainEntrance['limited_one_step_no_ramp'] = "#fc8d59"
$mainEntrance['no'] = "#d73027"

$keyMap = {}
#$keyMap['venue_name'] = 'Title'
#$keyMap['venue_type'] = 'Venue Type'
$keyMap['main_entrance_accessible'] = 'Main entrance access.'
$keyMap['main_door'] = 'Main door'
$keyMap['alt_accessible_entrance_ava'] = 'Alternative ent'
#$keyMap['separate_entrance_well_marked'] = 'Signs to alt'
#$keyMap['easy_navigation'] = 'Easy navigation'
$keyMap['restrooms_accessible'] = 'Restrooms accessible'
#$keyMap['staff_reponsive'] = 'Staff reponsive'
$keyMap['noise_level'] = 'Noise level'
$keyMap['venue_lat'] = 'venue_lat'
$keyMap['venue_lng'] = 'venue_lng'



locationOfCsvFile = "assessments_15nov14.csv"
csv_data = open(locationOfCsvFile).read()
csv = CSV.new(csv_data, :headers => :headers)

output = File.open( "assessments_15nov14.json", "w")
features = []
counter = 0;
csv.each do |row|
  counter = counter + 1
  #break if counter == 2
  feature = {}
  propertiesForGeoJson = {}
  assetProperties = {}
  row.each do | attribute |
    if $keyMap.has_key? attribute[0]
      propertiesForGeoJson[$keyMap[attribute[0]]] = attribute[1]
    end
  end
  feature['type'] = "Feature"
  feature['properties'] = propertiesForGeoJson
  feature['properties']['marker-color'] = $mainEntrance[propertiesForGeoJson['Main entrance access.']]
  geometry = {}
  geometry['type'] = "Point"
  geometry['coordinates'] = []
  geometry['coordinates'].push propertiesForGeoJson['venue_lng']
  geometry['coordinates'].push propertiesForGeoJson['venue_lat']
  feature['geometry'] = geometry
  features.push feature
end
geoWrapper = {}
geoWrapper['type'] = "FeatureCollection";
geoWrapper['features'] = features;
output.puts(geoWrapper.to_json)
output.close

