#!/usr/bin/env ruby
require 'sinatra'
require 'rubygems'
require 'rest_client'
require 'json'
require 'set'
require 'mongo'
require 'uri'
require 'pp'
require 'open-uri'
require 'date'

include Mongo

$stdout.sync = true

configure :production do
  require 'newrelic_rpm'
end

configure do
  db_details = URI.parse(ENV['MONGOHQ_URL'])
  conn = MongoClient.new(db_details.host, db_details.port)
  db_name = db_details.path.gsub(/^\//, '')
  db = conn.db(db_name)
  db.authenticate(db_details.user, db_details.password) unless (db_details.user.nil? || db_details.user.nil?)
  set :mongo_db, db
  set :appUrl, "http://map4access.herokuapp.com"
  enable :logging
  puts "dbconnection successful to #{ENV['MONGOHQ_URL']}"
end

get '/' do
  redirect "/places"
end

get '/places' do
  erb :places, :locals => {:page => "places", :page_title => "Find places nearby"}
end

get '/xhrnearbyplaces/:lat/:lng' do
  content_type :json
  getNearbyPlacesFromFoursquare(params[:lat], params[:lng], 10, 500).to_json
end

get '/xhrnearbyplacessearch/:lat/:lng/:query' do
  content_type :json
  getSearchResultsNearMeFromFoursquare(params[:lat], params[:lng], params[:query], 10, 5000).to_json
end


get '/xhrplacesnearnamedplace/:query/:near' do
  content_type :json
  getSearchResultsNearNamedPlace(URI.encode(params[:query]), params[:near], 20).to_json
end

get '/assess/:venueid' do
  venue = getVenueFromFoursquare(params[:venueid])
  venue_name = venue["response"]["venue"]["name"]
  categories = venue["response"]["venue"]["categories"]
  venue_type = "?"
  if (categories!=nil && categories.length > 0)
    venue_type = categories[0]["name"]
  end
  erb :assess, :locals => {:page => "assess", :page_title => "Assessing #{venue_name}, #{venue_type}", :venueid => params[:venueid], :venue => venue["response"]["venue"], :venue_name => venue_name, :venue_type => venue_type}
end

get '/reviews' do
  redirect "/places"
end

get '/postreviews/:venueid' do
  redirect "/assess/" + params[:venueid]
end

post '/assessment' do
  @pretty_json = JSON.pretty_generate(params)
  @assessment = params
  erb :assessment, :locals => {:page => "assessment", :page_title => "Your assessment"}
end

get '/assess_summary' do
  assessmentsCol = settings.mongo_db['assessments']
  assessmentsByType = assessmentsCol.aggregate([{"$group" => {_id: "$venue_type", assessments: {"$sum" => 1}}}])
  @byTypeHash= {}
  @total = 0
  assessmentsByType.each do | entry |
    @byTypeHash[entry["_id"]] = entry["assessments"]
    @total += entry["assessments"]
  end
  erb :assess_summary, :locals => {:page => "assess_summary", :page_title => "Assessment Summary"}
end

get '/assess_map' do
  erb :assess_map, :locals => {:page => "assess_map", :page_title => "Assessment Map (trial)"}
end

post '/postassessment' do
  assessmentsCol = settings.mongo_db['assessments']
  params['assessmentTimestamp'] = Time.new
  assessmentsCol.insert(params)
  erb :postassessment, :locals => {:page => "postassessment", :page_title => "Thanks for your help!"}
end

def getVenueFromFoursquare(venueid) 
  foursquare_id = ENV['FOURSQUARE_KEY']
  foursquare_secret = ENV['FOURSQUARE_SECRET']
  url = "https://api.foursquare.com/v2/venues/#{venueid}?client_id=#{foursquare_id}&client_secret=#{foursquare_secret}&v=20140715"
  response = RestClient.get url
  venue = JSON.parse(response)
  venue
end

def sendAlertMail(subject, body)
  if (ENV['MAIL_ACTIVE'] == 'true')
    message = Mail.new do
      from            ENV['ADMIN_EMAIL_FROM']
      to              ENV['ADMIN_EMAIL_TO']
      subject         subject
      body            body
      delivery_method Mail::Postmark, :api_key => ENV['POSTMARK_API_KEY']
    end
    message.deliver
  end
end

# Converts a street address to a GeoJSON object via the mapquest API
def getGeoJSON(address)  
  stationOutageTrackerCol = settings.mongo_db['geocodes']
  cache_result = stationOutageTrackerCol.find_one({:_id => address})
  if cache_result==nil # address doesn't exist in global variable
    mapquestKey = ENV['MAPQUEST_API_KEY']
    geocodeRequestUri = "http://open.mapquestapi.com/geocoding/v1/address?key=#{mapquestKey}&location=#{address}"
    geoCodeResponse = RestClient.get geocodeRequestUri
    jsonResults = JSON.parse(geoCodeResponse)
    if jsonResults['info']['statuscode'] == 403 # Request failed
      latLng = {"lng" => 0,"lat" => 0}
      latLng["_id"] = address
      stationOutageTrackerCol.insert(latLng)
    elsif jsonResults['results'][0]['locations'].length > 0
      latLng = jsonResults['results'][0]['locations'][0]['latLng']
      $yelpAddressLatLng[address] = latLng
      latLng["_id"] = address
      stationOutageTrackerCol.insert(latLng)
    else
      latLng = {"lng" => 0,"lat" => 0}
      latLng["_id"] = address
      stationOutageTrackerCol.insert(latLng)
    end
  else # address exists in global variable
    latLng = cache_result
  end
  return latLng
end

def getVenueFromFoursquare(venueid) 
  url = "https://api.foursquare.com/v2/venues/#{venueid}?#{getFsKeySecretVersionString()}"
  response = RestClient.get url
  venue = JSON.parse(response)
  venue
end

def getNearbyPlacesFromFoursquare(lat, lng, limit, radius) 
  url = "https://api.foursquare.com/v2/venues/search?ll=#{lat},#{lng}&limit=#{limit}&radius=#{radius}&#{getFsKeySecretVersionString()}" 
  response = RestClient.get url
  venue = JSON.parse(response)
  venue
end

def getSearchResultsNearMeFromFoursquare(lat, lng, query, limit, radius)
  url = "https://api.foursquare.com/v2/venues/search?ll=#{lat},#{lng}&query=#{query}&limit=#{limit}&radius=#{radius}&#{getFsKeySecretVersionString()}" 
  response = RestClient.get url
  venue = JSON.parse(response)
  venue
end

def getSearchResultsNearNamedPlace(query, near, limit) 
  url = "https://api.foursquare.com/v2/venues/search?query=#{query}&near=#{near}&limit=#{limit}&#{getFsKeySecretVersionString()}" 
  response = RestClient.get url
  venue = JSON.parse(response)
  venue
end

def getFsKeySecretVersionString()
  foursquare_key = ENV['FOURSQUARE_KEY']
  foursquare_secret = ENV['FOURSQUARE_SECRET']
  "client_id=#{foursquare_key}&client_secret=#{foursquare_secret}&v=20141015"
end
