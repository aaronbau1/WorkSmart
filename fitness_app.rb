require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "database_persistence"

configure do
  key = 'b302b9ae529b96802fcc4d702a7816b4023011661b428018860cb6bddf501983'
  enable :sessions
  set :session_secret, key
  set :erb, :escape_html => true
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "database_persistence.rb"
end

helpers do
  def format_time(time)
    hours, mins = time.split(':')
    case hours.to_i
    when 0
      "12:#{mins} AM"
    when 1..11
      "#{hours.to_i}:#{mins} AM"
    when 12
      "#{hours}:#{mins} PM"
    when 13..23
      "#{hours.to_i - 12}:#{mins} PM"
    end
  end

  def weekdays_array
    ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  end

  def items_per_page
    [1, 2, 5, 10]
  end

  def total_class_pages(ipp)
    classes = (@storage.total_class_amount).to_i
    classes == 0 ? 1 : (classes / ipp.to_f).ceil
  end

  def total_members_pages(ipp, id)
    members = @storage.class_member_count(id).to_i
    members == 0 ? 1 : (members / ipp.to_f).ceil
  end
  
  def total_member_class_pages(ipp, id)
    classes = (@storage.member_class_count(id)).to_i
    classes == 0 ? 1 : (classes / ipp.to_f).ceil
  end
  
  def all_members_pages(ipp)
    members = @storage.member_count.to_i
    members == 0 ? 1 : (members / ipp.to_f).ceil
  end

  def error_list
    session.delete(:error)
  end
end

def error_for_class_name(class_name)
  "Class name must be at least one character." if class_name.length < 1
end

def error_for_class_size(class_size)
  "Class size must be at least 1." if class_size.to_i <= 0
end

def error_for_class_time(start_time, end_time)
  errors = []
  start_hour, start_min = start_time.split(':')
  end_hour, end_min = end_time.split(':')

  if start_hour.to_i < 8 || end_hour.to_i > 20
    errors << "Class must start and end during gym hours (8:00 AM to 8:00 PM)."
  end

  condition1 = start_hour.to_i > end_hour.to_i
  condition2 = (start_hour == end_hour && start_min.to_i > end_min.to_i)

  if condition1 || condition2
    errors << "Start Time must be earlier than End Time."
  end
  errors
end

def error_for_first_name(first_name)
  "First name must be at least one character." if first_name.length < 1
end

def error_for_last_name(last_name)
  "Last name must be at least one character." if last_name.length < 1
end

def error_for_phone_number(phone_number)
  if phone_number !~ (/^[\d]{3}-[\d]{3}-[\d]{4}/)
    "Phone number must be in the specified format: 123-456-7890"
  elsif !@storage.unique_member_entry(phone_number, "phone_number")
    "This phone number is associated with a different member."
  end
end

def error_for_username(username)
  if username.length < 1
    "Username must be at least one character."
  elsif !@storage.unique_member_entry(username, "username")
    "That username is already in use."
  end
end

def error_for_password(password, check)
  errors = []
  if password.length < 7
    errors << "Password must be at least 7 characters."
  end

  if password != check
    errors << "The two password entries do not match."
  end
  errors
end

def check_for_enrollment_errors(username, roster, class_info)
  if roster.any? { |member| member[:username] == username }
    "You are already enrolled in this class."
  elsif username == class_info[:instructor]
    "The instructor can not enroll in the class."
  elsif class_info[:open_spots] <= 0
    "This class has no more open spots left."
  end
end

def username_to_full_name(username)
  unless username.nil?
    result = @storage.get_member_info(username)
    "#{result[:first_name]} #{result[:last_name]}"
  end
end

def login_check
  if session[:username].nil?
    session[:error] = ["You must be logged in to perform this action."]
    session[:login_redirect_url] = request.path_info
    redirect "/login"
  end
end

def instructor_check
  if session[:instructor] == false
    session[:error] = ["You must be an instructor to perform this action."]
    redirect "/classes"
  end
end

def class_instructor_check(id)
  name = @storage.get_class_details(id)[:instructor]
  if session[:username] != name
    msg = "You must be the class instructor to perform this action."
    session[:error] = [msg]
    redirect "/classes"
  end
end

def class_check(id)
  unless @storage.class_exists?(id)
    session[:error] = ["That class does not exist."]
    redirect "/classes"
  end
end

def member_id_check(id)
  unless @storage.member_exists?(id)
    session[:error] = ["That member does not exist."]
    redirect "/classes"
  end
end

def plant_seed_data
  # populates database with seed data
  system("psql -d fitness_center < data/tables_and_data.sql")
end

def logout
  session.delete(:username)
  session.delete(:instructor)
  session.delete(:login_redirect_url)
end

before do
  system("sudo service postgresql start")
  #checks if database exists
  db_check = system("sudo -u postgres psql -c 
            ""SELECT * FROM pg_database WHERE datname = 'fitness_center'")
  unless db_check
    system("createdb fitness_center")
  end
  @storage = DatabasePersistence.new(logger)
end

get "/" do
  plant_seed_data
  session.clear
  redirect "/classes"
end

# View all available classes
get "/classes" do
  @page = params[:page] || 1
  @ipp = params[:ipp] || 5
  @sort = params[:sort] || "ASC"

  @page = @page.to_i
  @ipp = @ipp.to_i

  errors = []
  if !items_per_page.include?(@ipp)
    errors << "Not a valid Items Per Page selection."
  end

  if !(1..total_class_pages(@ipp)).cover?(@page)
    errors << "That page does not exist."
  end

  if errors.none?
    offset = @ipp * (@page - 1)
    @classes = @storage.all_classes(@ipp, offset, @sort)
    
    @member = @storage.get_member_info(session[:username]) if session[:username]
    erb :classes, layout: :layout
  else
    session[:error] = errors
    redirect "/classes"
  end
end

# View the new class form
get "/classes/new" do
  login_check
  instructor_check

  @instructor = username_to_full_name(session[:username])
  erb :new_class, layout: :layout
end

# Submit a new class form
post "/classes/new" do
  login_check
  instructor_check

  # validate inputs
  errors = []
  class_name_err = error_for_class_name(params[:name].strip)
  class_size_err = error_for_class_size(params[:class_size])
  class_time_err = error_for_class_time(params[:start_time], params[:end_time])

  if class_name_err
    errors << class_name_err
    params[:name] = nil
  end

  if class_size_err
    errors << class_size_err
    params[:class_size] = nil
  end

  if class_time_err.any?
    class_time_err.each { |err| errors << err }
    params[:start_time] = nil
    params[:end_time] = nil
  end

  if errors.none?
    @storage.create_new_class(params[:name], session[:username],
                              params[:class_size], params[:day],
                              params[:start_time], params[:end_time])
    session[:success] = "The class has been created."
    redirect "/classes"
  else
    session[:error] = errors
    erb :new_class, layout: :layout
  end
end

# Delete a class
post "/classes/:id/delete" do
  id = params[:id].to_i
  login_check
  class_check(id)
  class_instructor_check(id)

  @storage.delete_class(id)
  session[:success] = "The class has been deleted."
  redirect back
end

# Edit an existing class
get "/classes/:id/edit" do
  id = params[:id].to_i
  login_check
  class_check(id)
  class_instructor_check(id)

  @class = @storage.get_class_details(id)
  erb :edit_class, layout: :layout
end

# Submut edits to a class form
post "/classes/:id/edit" do
  id = params[:id].to_i
  login_check
  class_check(id)
  class_instructor_check(id)

  @class = @storage.get_class_details(id)

  # validate inputs
  errors = []
  class_name_err = error_for_class_name(params[:name].strip)
  class_size_err = error_for_class_size(params[:class_size])
  class_time_err = error_for_class_time(params[:start_time], params[:end_time])

  if class_name_err
    errors << class_name_err
    params[:name] = nil
  end

  if class_size_err
    errors << class_size_err
    params[:class_size] = nil
  end

  if class_time_err.any?
    class_time_err.each { |err| errors << err }
    params[:start_time] = nil
    params[:end_time] = nil
  end

  if errors.none?
    @storage.edit_class(params[:name], session[:username], params[:class_size],
                        params[:day], params[:start_time],
                        params[:end_time], id)
    session[:success] = "The class has been updated."
    redirect "/classes"
  else
    session[:error] = errors
    erb :edit_class, layout: :layout
  end
end

# View a specific class page
get "/classes/:id/view" do
  @id = params[:id].to_i
  
  login_check
  class_check(@id)

  @page = params[:page] || 1
  @ipp = params[:ipp] || 5
  @sort = params[:sort] || "ASC"

  @page = @page.to_i
  @ipp = @ipp.to_i

  errors = []
  if !items_per_page.include?(@ipp)
    errors << "Not a valid Items Per Page selection."
  end

  if !(1..total_members_pages(@ipp, @id)).cover?(@page)
    errors << "That page does not exist."
  end

  if errors.none?
    @offset = @ipp * (@page - 1)
    @class = @storage.get_class_details(@id)
    @class_roster_display = @storage.get_class_roster_display(@id, @ipp,
                                                              @offset, @sort)
    @class_roster = @storage.get_class_roster(@id)
    erb :view_class, layout: :layout
  else
    session[:error] = errors
    redirect "classes/#{@id}/view"
  end
end

# Enroll a member in a class
post "/classes/:id/view" do
  id = params[:id].to_i
  login_check
  class_check(id)

  @class = @storage.get_class_details(id)
  @class_roster = @storage.get_class_roster(id)
  @member = @storage.get_member_info(session[:username])
  error = check_for_enrollment_errors(session[:username], @class_roster, @class)

  if error.nil?
    @storage.add_to_class_roster(@class[:id], @member[:id])
    session[:success] = "You have enrolled in #{@class[:name]}!"
  else
    session[:error] = [error]
  end
  redirect "/classes/#{id}/view"
end

# Drop a member from a class
post "/classes/:id/drop" do
  id = params[:id].to_i
  login_check
  class_check(id)
  
  @class = @storage.get_class_details(id)
  @class_roster = @storage.get_class_roster(id)
  @member = @storage.get_member_info(session[:username])

  if @class_roster.any? { |member| member[:username] == (session[:username]) }
    @storage.drop_from_class_roster(@class[:id], @member[:id])
    session[:success] = "You are no longer enrolled in #{@class[:name]}."
  else
    session[:error] = ["You are not enrolled in this class."]
  end
  redirect back
end

get "/members/:id/view" do
  @id = params[:id].to_i
  login_check
  member_id_check(@id)
  @member = @storage.get_member_info(session[:username])
  
  @page = params[:page] || 1
  @ipp = params[:ipp] || 1
  @sort = params[:sort] || "ASC"

  @page = @page.to_i
  @ipp = @ipp.to_i
  
  errors = []
  if @id != @member[:id]
    session[:error] =  ["You do not have access to this page"]
    redirect "/classes"
  end

  if !items_per_page.include?(@ipp)
    errors << "Not a valid Items Per Page selection."
  end

  if !(1..total_member_class_pages(@ipp, @id)).cover?(@page)
    errors << "That page does not exist."
  end

  if errors.none?
    @offset = @ipp * (@page - 1)
    @member_enrollment = @storage.get_member_enrollment(@id, @ipp, @offset, @sort)
    if session[:instructor]
      @instructor_classes = @storage.get_instructor_classes(session[:username])
    end
    erb :view_member, layout: :layout
  else
    session[:error] = errors
    redirect "/members/#{@id}/view"
  end
end

get "/members/:id/edit" do
  @id = params[:id].to_i
  login_check
  member_id_check(@id)
  @member = @storage.get_member_info(session[:username])
  if @id != @member[:id]
    session[:error] = ["You do not have access to this page"]
    redirect "/classes"
  end
  erb :edit_member, layout: :layout
end

post "/members/:id/edit" do
  @id = params[:id].to_i
  login_check
  member_id_check(@id)
  @member = @storage.get_member_info(session[:username])
  if @id != @member[:id]
    session[:error] = ["You do not have access to this page"]
    redirect "/classes"
  end
  
  # validate inputs
  errors = []
  first_name_err = error_for_first_name(params[:first_name].strip)
  last_name_err = error_for_last_name(params[:last_name].strip)
  
  if @member[:phone_number] != params[:phone_number]
    number_err = error_for_phone_number(params[:phone_number])
  end
  
  if @member[:username] != params[:username]
    username_err = error_for_username(params[:username].strip)
  end

  if first_name_err
    errors << first_name_err
    params[:first_name] = nil
  end

  if last_name_err
    errors << last_name_err
    params[:last_name] = nil
  end

  if number_err
    errors << number_err
    params[:phone_number] = nil
  end

  if username_err
    errors << username_err
    params[:username] = nil
  end

  if errors.none?
    @storage.update_member(params[:first_name], params[:last_name],
                              params[:phone_number], params[:username], @id)
    session[:success] = "Your information was updated."
    redirect "/members/#{@id}/view"
  else
    session[:error] = errors
    erb :edit_member, layout: :layout
  end
end

post "/members/:id/delete" do
  @id = params[:id].to_i
  login_check
  member_id_check(@id)
  @member = @storage.get_member_info(session[:username])
  if @id != @member[:id]
    session[:error] = ["You do not have access to this page"]
    redirect "/classes"
  end
  
  if session[:instructor]
    session[:error] = ["Instructor accounts can only be deleted by admins."]
    redirect back
  end
  
  @storage.delete_member(@id)
  session[:success] = "Your account has been deleted."
  logout
  redirect "/classes"
end

get "/members/all" do
  login_check
  instructor_check
  
  @page = params[:page] || 1
  @ipp = params[:ipp] || 5
  @sort = params[:sort] || "ASC"

  @page = @page.to_i
  @ipp = @ipp.to_i
  
  errors = []

  if !items_per_page.include?(@ipp)
    errors << "Not a valid Items Per Page selection."
  end
 
  if !(1..all_members_pages(@ipp)).cover?(@page)
    errors << "That page does not exist."
  end

  if errors.none?
    @offset = @ipp * (@page - 1)
    @members = @storage.get_all_member_info(@ipp, @offset, @sort)
    erb :all_members, layout: :layout
  else
    session[:error] = errors
    redirect '/members/all'
  end
end

get "/signup" do
  erb :new_member, layout: :layout
end

post "/signup" do
  # validate inputs
  errors = []
  first_name_err = error_for_first_name(params[:first_name].strip)
  last_name_err = error_for_last_name(params[:last_name].strip)
  number_err = error_for_phone_number(params[:phone_number])
  username_err = error_for_username(params[:username].strip)
  password_err = error_for_password(params[:password].strip,
                                    params[:verify_password].strip)

  if first_name_err
    errors << first_name_err
    params[:first_name] = nil
  end

  if last_name_err
    errors << last_name_err
    params[:last_name] = nil
  end

  if number_err
    errors << number_err
    params[:phone_number] = nil
  end

  if username_err
    errors << username_err
    params[:username] = nil
  end

  if password_err.any?
    password_err.each { |err| errors << err }
    params[:password] = nil
    params[:verify_password] = nil
  end

  if errors.none?
    @storage.create_new_member(params[:first_name], params[:last_name],
                               params[:phone_number], params[:username],
                               params[:password], false)
    session[:success] =
      "Welcome to the Launch School Fitness Center, #{params[:first_name]}!"
    redirect "/login"
  else
    session[:error] = errors
    erb :new_member, layout: :layout
  end
end

get "/login" do
  erb :login, layout: :layout
end

post "/login" do
  if @storage.valid_credentials?(params[:username], params[:password])
    username = params[:username]
    @member = @storage.get_member_info(username)
    first_name = @member[:first_name]
    session[:username] = username
    session[:instructor] = (@member[:instructor] == "t")
    session[:success] =
      "Welcome back to the Launch School Fitness Center, #{first_name}!"
    redirect session[:login_redirect_url] || "/classes"
  else
    session[:error] = ["Invalid Username or Password"]
    erb :login, layout: :layout
  end
end

post "/logout" do
  logout
  session[:success] = "You have been logged out."
  redirect '/classes'
end
