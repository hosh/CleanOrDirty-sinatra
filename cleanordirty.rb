#require 'rubygems'
#require 'bundler/setup'
require 'time'

require 'datamapper'
require 'dm-core'
require 'dm-migrations'
require 'dm-validations'
require 'dm-serializer'

require 'sinatra'
require 'bitly'


# set up database using datamapper

class Dishwasher
  include DataMapper::Resource

  # fields
  property :id,             Serial
  property :name,           String
  property :status,         String
  property :code,           String
  property :last_updated,   Integer
  # validations
  validates_uniqueness_of :code

  before :create, :set_defaults
  after  :create, :set_url_code
  
  # Acceptor pattern (complement of Presenter pattern)
  def self.accept_params(params)
    params.delete("code") # can't update code
    params.delete("name") if params["name"].blank?
    params.delete("status") if params["status"].blank?

    params['last_updated'] = params['last_updated'].to_i  # nil.to_i is 0. ''.to_i is 0 

    return params
  end
  
  private

  def set_defaults
    self.status ||= "dirty"
    self.last_updated ||= Time.now.utc.to_i
  end

  def set_url_code
    self.code = $bitly.shorten("http://cleanordirty.heroku.com/api/v1/dishwashers/#{dishwasher.id}").user_hash
  end

end

DataMapper.finalize

# Set up database logs
DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/db/project.db")

Dishwasher.auto_migrate! unless Dishwasher.storage_exists?

Bitly.use_api_version_3
$bitly = Bitly.new("plusbzz", "<your api key here>")



before do
  content_type 'application/json'
end

# the HTTP entry points to our service

get '/api/v1/dishwashers/:code' do
  dishwasher = Dishwasher.first(:code => params[:code])
  return error 404, 'diswasher not found'.to_json unless dishwasher
  return dishwasher.to_json
end

post '/api/v1/dishwashers' do
  begin
    body = JSON.parse(request.body.read)
    dishwasher = Dishwasher.create(body)
    
    return error 400, "error creating dishwasher".to_json if dishwasher.new?
    return dishwasher.to_json
  rescue => e
    error 400, e.message.to_json
  end
end


# TODO validate updates
#     cannot update code
#     status should be clean or dirty
#     name should be bounded

post '/api/v1/dishwashers/update/:code' do
  dishwasher = Dishwasher.first(:code => code)
  return error 404, "dishwasher not found".to_json unless dishwasher

  begin
    params = Dishwasher.accept_params(JSON.parse(request.body.read))
    dishwasher.update(body) if params['last_updated'] > dishwasher.last_updated
    dishwasher.to_json
  rescue => e
    error 400, e.message.to_json
  end
end

delete_dishwasher = proc do
  dishwasher = Dishwasher.first(:code => code)
  return error 404, "dishwasher not found".to_json unless dishwasher

  dishwasher.destroy
  return dishwasher.to_json # This really should be returning something like 200 OK without content
end

delete('/api/v1/dishwashers/:code', &delete_dishwasher)
post('/api/v1/dishwashers/delete/:code', &delete_dishwasher) 
