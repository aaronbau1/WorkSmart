Sinatra app for fitness center webapp

Version of Ruby used: ruby 2.6.3
Version of Chrome used: 114.0.5735.199
Version of PostgreSQL used: 13.7

Installation:

Using Amazon Cloud9 webservices, create an environment and upload the
uncompressed files using File -> Upload Local Files

Description of Files Included:

Gemfile and Gemfile.lock: Configuration files to gather the required Ruby gems
                          for the web application to run.
                          
fitness_app.rb: Sinatra file that executes the routing and business logic
                of the application

database_persistence.rb: Ruby file that holds all logic that interacts with the
                          PostgreSQL database.

Views folder: Holds all erb files that interact with fitness_app.rb to display
              the front end of the web application.
              
Public folder: Holds the css files that interact with fitness_app.rb to display
              the front end of the web application.
              
Data folder: Contains an SQL file that configures the PostgreSQL database,
              populating the database with tables and initial seed data.
              
              NOTE: All password credentials for the initial seed data are "password"

Instructions to run the application:

To run the application type the command "sudo service postgresql start" in the terminal
to initiate the PostgreSQL server. To install all of the necessary gems for the
app, execute "bundle install" in the directory that the Gemfile is located.
Go to the directory that holds fitness_app.rb and execute the command 
"ruby fitness_app.rb" into the terminal. Upon startup a new
database will be created for the app if it doesn't exist. Requesting the route "/" 
will populate the PostgreSQL database with all necessary tables and seed data 
so that the functions of the app can be demonstrated.

If there is a desire to reset the seed data, just request the route "/" which
will redirect you to "/classes".

Description and Features of the Web Application:

Note: All passwords are "password" for seed data member password logins

This is an application for the Launch School Fitness Center to display the 
fitness classes that they offer, as well as provide services for members to enroll
and drop in these classes.

On the homepage "/classes", users can see the open classes available and information
pertaining to them. Classes can be sorted alphabetically and by items per page.
Each class can be viewed to see the current members that are enrolled in the class.
The members enrolled can be sorted alphabetically and by items per page. 
If there are open spots available, a member can enroll in this class. If a member
is enrolled in the class, they can drop from this class as well.

There are 3 levels of permissions within the app: 

Non-members: Can only view the homepage, log in, or sign up to become a member. 

Members: Can view classes and the members that are currently enrolled in those classes.
          Members also have the ability to enroll or drop from these classes. 

Instructors: Can create new classes and have the ability to edit or delete 
              classes that they have created.

Sample member credentials: username: ink, password: password
Sample instructor credentials: username: dw40, password: password
