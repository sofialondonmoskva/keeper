require 'sinatra'
require 'active_record'
require 'active_support/time'
require 'json'
require 'cgi'
require 'logger'
ROOT = File.dirname(__FILE__)
CONFIG = File.join(ROOT,'config.rb')

# just use sqlite3 if there is no config file
File.open(CONFIG,"w") { |f| f.write(%Q{ActiveRecord::Base.establish_connection(:adapter => 'sqlite3',:database => File.join(ROOT,"db.sqlite3"))\n}) } unless File.exists?(CONFIG)
require File.join(ROOT,'config.rb')

ActiveRecord::Base.logger = Logger.new STDOUT unless (ENV["RACK_ENV"] == "production")

MAX_PRODUCTIVITY = 2
MIN_PRODUCTIVITY = -3
AGGREGATE = 300
UID_LEN = 128
UID_RE = "[a-zA-Z0-9]{#{UID_LEN}}"
MAX_REQUESTS_PER_DAY = 1000
THROTTLE = {}
def humanize(secs)
  [[60, :s], [60, :m], [24, :h], [1000, :d]].inject([]){ |s, (count, name)|
    if secs > 0
      secs, n = secs.divmod(count)
      s.unshift "#{n.to_i}#{name}"
    end
    s
  }.join(' ')
end

class Fixnum
  def ms
    self * 1000
  end
  def ms_to_s
    self > 1000 ? self/1000 : 1
  end
end

class String
  def escape
    CGI.escapeHTML(self)
  end
end

class User < ActiveRecord::Base
  has_many :applications,dependent: :destroy
  attr_accessible :uid,:todays_productivity
  validates :uid, presence: true, uniqueness: true
end

class Application < ActiveRecord::Base
  has_many :samples, dependent: :destroy
  attr_accessible :name, :productivity, :user_id
  belongs_to :user
  validates :user, presence: true
  validates :name, presence: true
  scope :ignored, where(productivity: MIN_PRODUCTIVITY)
  scope :not_ignored, where("productivity > ?",MIN_PRODUCTIVITY)
  def productive?
    self.productivity > 0
  end
  def productive!(dir = :up)
    if dir == :up
      self.productivity += 1 if self.productivity < MAX_PRODUCTIVITY
    else
      self.productivity -= 1 if self.productivity > MIN_PRODUCTIVITY 
    end
    self.save!
  end
end

class Sample < ActiveRecord::Base
  belongs_to :application
  attr_accessible :seconds,:stamp, :application_id
  validates :application, presence: true
end

def throttle(ip, input = 1)
  key = "#{ip}_#{Time.now.to_i / 1.day}"
  THROTTLE[key] ||= 0
  THROTTLE[key] += input
  return THROTTLE[key] > MAX_REQUESTS_PER_DAY
end

class App < Sinatra::Base
  set :sessions, false
  set :logging, true
  #set :dump_errors, false
  #set :show_exceptions, false
  set :static, false

  error 404 do
    "nop, not found"
  end

  error 400 do
    "bad, very bad"
  end

  post %r{/(#{UID_RE})/input/([0-9]+)} do |uid,stamp|
    user = User.find_by_uid(uid) or error 404
    input = JSON.parse(request.env["rack.input"].read) rescue {}
    stamp = (stamp.to_i / AGGREGATE) * AGGREGATE

    error 400 if throttle(request.ip,input.keys.count) 
    begin
      Sample.transaction do
        input.each do |k,v|
          app = Application.lock.where(name: k.to_s.escape, user_id: user.id).first_or_create!
          s = Sample.where(application_id: app.id, stamp: stamp).first_or_initialize
          s.seconds ||= 0
          s.seconds += v.to_i
          s.save
        end
      end
    rescue ActiveRecord::RecordInvalid => exception
      warn exception.message
      error 400
    end
    stamp
  end
  def keep_time
    "from=#{@from.ms}&to=#{@to.ms}"
  end
  get %r{/(#{UID_RE})/report/} do |uid|
    @user = User.find_by_uid(uid) or error 404

    @from = (params[:from].to_i > 0 ? params[:from].to_i : Time.now.utc.beginning_of_day.to_i.ms).ms_to_s
    @to = (params[:to].to_i > 0 ? params[:to].to_i :  Time.now.utc.end_of_day.to_i.ms).ms_to_s

    if params[:application]
      app = @user.applications.find(params[:application]) rescue nil
      error 404 unless app
      begin
        if params[:delete]
          app.destroy
        else
          app.productive!(params[:up] ? :up : :down)
        end
      rescue Exception => exception
        warn exception.message
      end
      redirect "/#{uid}/report/?from=#{@from.ms}&to=#{@to.ms}"
    end

    @applications = @user.applications.not_ignored.find(:all,
                                        select: "applications.*,sum(samples.seconds) as duration",
                                         joins: :samples,
                                    conditions: {"samples.stamp" => @from..@to},
                                         group: "applications.id",
                                         limit: 20,
                                         order: 'duration DESC')
    @ignored = @user.applications.ignored

    @stamps = Hash.new(0)
    person = 0.0
    robot = 0.0
    @activity = 0
    Sample.find(:all,
             select: "samples.*, applications.productivity as ap",
              joins: :application,
         conditions: { application_id: @applications.map { |x| x.id }, stamp: @from..@to},
              order: :stamp).each do |s|
      robot += MAX_PRODUCTIVITY
      person += s.ap
      @stamps[s.stamp] += s.ap
      @activity += s.seconds
    end
    @productivity = ((person/robot) * 100.0).round rescue 0.0
    
    erb :report
  end

  get '/generate/uid/' do
    error 400 if throttle(request.ip)

    u = User.new(uid: SecureRandom.hex(UID_LEN/2))
    u.save!
    u.uid.to_s
  end

  get '/' do
    redirect "https://github.com/sofialondonmoskva/keeper/"
  end
end
if ARGV[0] == 'db:migrate'
  class CreateTables < ActiveRecord::Migration
    def change
      create_table :users do |t|
        t.string        :uid, null: false, default: nil
        t.timestamps
      end

      create_table :applications do |t|
        t.integer       :user_id, null: false, default: nil
        t.string        :name, null: false, default: nil
        t.integer       :productivity, null: false, default: 0
      end

      create_table :samples do |t|
        t.integer       :application_id, null: false, default: nil
        t.integer       :seconds, null: false, default: nil
        t.integer       :stamp, null: false, default: nil
      end
      add_index('users', 'uid')
      add_index('applications', 'user_id')
      add_index('applications', 'productivity')
      add_index('samples', 'application_id')
      add_index('samples', 'stamp')
    end
  end
  if ARGV[1] == 'down'
    CreateTables.migrate(:down)
  else
    CreateTables.migrate(:up)
  end
  exit 0
end

