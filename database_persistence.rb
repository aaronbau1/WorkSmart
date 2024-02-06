require "pg"
require "bcrypt"

# For fitness center app
class DatabasePersistence
  def initialize(logger)
    @db = PG.connect(dbname: "fitness_center")
    @logger = logger
  end
  
  def query(statement, *params)
    @logger.info "#{statement}: #{params}"
    @db.exec_params(statement, params)
  end
  
  def all_classes(limit, offset, sort)
    sql = <<~SQL
    SELECT c.*, (c.class_size - COUNT(cm.classes_id)) AS open_spots
    FROM classes AS c
    LEFT JOIN classes_members AS cm ON c.id = cm.classes_id
    GROUP BY c.id
    ORDER BY c.name #{sort}
    LIMIT #{limit}
    OFFSET #{offset};
    SQL

    result = query(sql)
    result.map do |tuple|
      tuple_to_class_hash(tuple)
    end
  end
  
  def create_new_class(name, instructor, class_size, day, start_time, end_time)
    sql = "INSERT INTO classes (name, instructor, class_size, day, start_time, end_time) 
    VALUES ($1, $2, $3, $4, $5, $6)"
    
    query(sql, name, instructor, class_size, day, start_time, end_time)
  end
  
  def edit_class(name, instructor, class_size, day, start_time, end_time, id)
    sql = "UPDATE classes SET name = $1, instructor = $2, class_size = $3, 
          day = $4, start_time = $5, end_time = $6 WHERE id = $7"
    
    query(sql, name, instructor, class_size, day, start_time, end_time, id)
  end
  
  def delete_class(id)
    sql = "DELETE FROM classes WHERE id = $1"
    query(sql, id)
  end
  
  def total_class_amount
    sql = "SELECT COUNT(id) FROM classes;"
    query(sql)[0]["count"]
  end
  
  def class_member_count(id)
    sql = "SELECT COUNT(id) FROM classes_members WHERE classes_id = $1;"
    query(sql, id)[0]["count"]
  end
  
  def member_count
    sql = "SELECT COUNT(id) FROM members"
    query(sql)[0]["count"]
  end
  
  def member_class_count(id)
    sql = "SELECT COUNT(id) FROM classes_members WHERE members_id = $1;"
    query(sql, id)[0]["count"]
  end
  
  def class_exists?(id)
    sql = "SELECT * FROM classes WHERE id = $1;"
    query(sql, id).ntuples == 1
  end
  
  def member_exists?(id)
    sql = "SELECT * FROM members WHERE id = $1;"
    query(sql, id).ntuples == 1
  end
  
  def get_class_details(id)
    sql = <<~SQL
    SELECT c.*, (c.class_size - COUNT(cm.classes_id)) AS open_spots
    FROM classes AS c
    LEFT JOIN classes_members AS cm ON c.id = cm.classes_id
    WHERE c.id = $1
    GROUP BY c.id
    ORDER BY c.name;
    SQL
    
    result = query(sql, id)
    tuple_to_class_hash(result.first)
  end
  
  def get_class_roster_display(id, limit, offset, sort)
    sql = <<~SQL
    SELECT m.id, m.username, m.first_name, m.last_name
    FROM classes_members AS cm
    LEFT JOIN members AS m ON cm.members_id = m.id
    WHERE cm.classes_id = $1
    ORDER BY m.last_name #{sort}
    LIMIT #{limit}
    OFFSET #{offset};
    SQL
    
    result = query(sql, id)
    result.map do |tuple|
      tuple_to_member_info(tuple)
    end
  end
  
  def get_class_roster(id)
    sql = <<~SQL
    SELECT m.id, m.username, m.first_name, m.last_name
    FROM classes_members AS cm
    LEFT JOIN members AS m ON cm.members_id = m.id
    WHERE cm.classes_id = $1
    ORDER BY m.last_name;
    SQL
    
    result = query(sql, id)
    result.map do |tuple|
      tuple_to_member_info(tuple)
    end
  end
  
  def get_member_enrollment(id, limit, offset, sort)
    sql = <<~SQL
    SELECT c.*
    FROM classes_members AS cm
    LEFT JOIN classes AS c ON c.id = cm.classes_id
    WHERE cm.members_id = $1
    GROUP BY c.id
    ORDER BY c.name #{sort}
    LIMIT #{limit}
    OFFSET #{offset};
    SQL
    
    result = query(sql, id)
    result.map do |tuple|
      tuple_to_class_hash(tuple)
    end
  end
  
  def get_instructor_classes(username)
    sql = <<~SQL
    SELECT c.*
    FROM classes_members AS cm
    LEFT JOIN classes AS c ON c.id = cm.classes_id
    WHERE c.instructor = $1
    GROUP BY c.id
    ORDER BY c.name;
    SQL
    
    result = query(sql, username)
    result.map do |tuple|
      tuple_to_class_hash(tuple)
    end
  end
  
  def add_to_class_roster(classes_id, members_id)
    sql = "INSERT INTO classes_members (classes_id, members_id) VALUES ($1, $2)"
    query(sql, classes_id, members_id)
    p "success"
  end
  
  def drop_from_class_roster(classes_id, members_id)
    sql = "DELETE FROM classes_members WHERE classes_id = $1 AND members_id = $2"
    query(sql, classes_id, members_id)
  end
  
  def create_new_member(first_name, last_name, phone_number, username, password, instructor)
    sql = "INSERT INTO members (first_name, last_name, phone_number, username, password, instructor)
            VALUES ($1, $2, $3, $4, $5, $6)"
    bcrypt_password = BCrypt::Password.create(password)
    query(sql, first_name, last_name, phone_number, username, bcrypt_password, instructor)
  end
  
  def update_member(first_name, last_name, phone_number, username, id)
    sql = "UPDATE members SET first_name = $1, last_name = $2, phone_number = $3,
          username = $4 WHERE id = $5"
    query(sql, first_name, last_name, phone_number, username, id)
  end
  
  def delete_member(id)
    sql = "DELETE FROM members WHERE id = $1"
    query(sql, id)
  end
  
  def unique_member_entry(input, column)
    sql = "SELECT id FROM members WHERE #{column} = $1"
    query(sql, input).ntuples == 0
  end
  
  def valid_credentials?(username, password)
    sql = "SELECT password FROM members WHERE username = $1"
    credentials = query(sql, username)
    credentials.each do |tuple|
      bcrypt_password = BCrypt::Password.new(tuple["password"])
      return true if bcrypt_password == password
    end
    false
  end
  
  def get_member_info(username)
    sql = "SELECT * FROM members WHERE username = $1"
    result = query(sql, username)
    tuple_to_member_info(result.first)
  end
  
  def get_all_member_info(limit, offset, sort)
    sql = <<~SQL
    SELECT first_name, last_name, phone_number
    FROM members 
    ORDER BY last_name #{sort}
    LIMIT #{limit}
    OFFSET #{offset};
    SQL
    
    result = query(sql)
    result.map do |tuple|
      tuple_to_member_info(tuple)
    end
  end
  
  private 
  def tuple_to_class_hash(tuple)
    {id: tuple["id"].to_i, 
      name: tuple["name"],
      instructor: tuple["instructor"],
      class_size: tuple["class_size"].to_i,
      day: tuple["day"],
      start_time: tuple["start_time"],
      end_time: tuple ["end_time"],
      open_spots: tuple["open_spots"].to_i
      }
  end
  
  def tuple_to_member_info(tuple)
    {id: tuple["id"].to_i,
      first_name: tuple["first_name"],
      last_name: tuple["last_name"],
      username: tuple["username"],
      instructor: tuple["instructor"],
      phone_number: tuple["phone_number"]
    }
  end
end