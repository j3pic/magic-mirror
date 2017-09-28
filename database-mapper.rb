require "#{File.dirname(__FILE__)}/force_loader.rb"

$unresolved_errors = resolve_dependencies begin
                                            errors=force_load_from_path + force_load_all_models
                                            puts "Resolving dependencies..."
                                            errors
                                          end
def ignore_errors
  yield
rescue Exception => e
  nil
end

def connection_info(model)
  model.connection_config[:makara]["connections"][0].slice( "host", "port", "database")
end

def same_connection?(model_a, model_b)
  connection_info(model_a) == connection_info(model_b)
end

puts "Looking for database connections..."

CONNECTION_MODELS=->(result) {
  MagicMirror.apropos_data(//, match_methods: false).each do |klass|
    ignore_errors do
      unless klass == "ActiveRecord::Fixtures"
        k=klass.constantize
        if (k.is_a?(Class) && (k < ActiveRecord::Base) && !result.find do |model|
             same_connection? model, k
            end)
          result << k
        end
      end
    end
  end
  result
}.call([])

puts "Building DB table->Ruby class lookup table"

DATABASE_TABLE_LOOKUP = {}

def add_database_table_ref(model)
  DATABASE_TABLE_LOOKUP[model.table_name] ||= []
  DATABASE_TABLE_LOOKUP[model.table_name] << model
end

MagicMirror.apropos_data(//, match_methods: false).each do |klass|
  begin
    if klass != "ActiveRecord::Fixtures"
      k = klass.constantize
      if k.is_a?(Class) && (k < ActiveRecord::Base) && k.table_name.is_a?(String)
        add_database_table_ref(k)
      end
    end
  rescue Exception => e
    nil
  end
end

def find_database_model(table_name)
  MagicMirror.apropos_data(//, match_methods: false).select do |klass|
    ignore_errors do
      unless klass == "ActiveRecord::Fixtures"
        k = klass.constantize
        k.is_a?(Class) && (k < ActiveRecord::Base) && k.table_name == table_name
      end
    end
  end.uniq
end

def find_database_model(table_name)
  DATABASE_TABLE_LOOKUP[table_name]
end

def tables_with_links(connection)
  connection.execute(%{ select distinct table_name from information_schema.columns where column_name like '%\_id'; }).map do |row|
    row["table_name"]
  end
end

def get_pertinent_models(connection)
  models = []
  unknown_tables = []
  tables_with_links(connection).each do |table|
    result = find_database_model(table) || []
    if result.length > 0
      models += result.select do |obj|
        obj.connection == connection
      end
    else
      unknown_tables << table
    end
  end
  { models: models,
    unknown_tables: unknown_tables }
end

def get_all_models
  result={ models: [],
           unknown_tables: [] }
  (CONNECTION_MODELS.map do |model|
     model.connection
   end.each do |conn|
     local_result=get_pertinent_models(conn)
     result[:models] += local_result[:models]
     result[:unknown_tables] += local_result[:unknown_tables]
   end)
  result
end

def get_foreign_keys(model)
  errors=[]
  associations=model.reflections.symbolize_keys.map do |key,reflection|
    begin
      other_table_class = if reflection.polymorphic?
                            nil
                          elsif reflection.class == ActiveRecord::Reflection::ThroughReflection
                            begin
                              ActiveSupport::Inflector.camelize(reflection.delegate_reflection.options[:through]).constantize
                            rescue Exception => e
                              nil
                            end
                          else
                            reflection.klass
                          end
      other_table = if other_table_class.respond_to?(:table_name) && other_table_class.table_name
                      other_table_class.table_name
                    end
      real_reflection = reflection
      reflection = if reflection.class == ActiveRecord::Reflection::ThroughReflection
                     reflection.delegate_reflection
                   else
                     reflection
                   end
      { association_type: real_reflection.class,
        ruby_name: key,
        ruby_class: (if reflection.polymorphic?
                     Object
                    else
                      reflection.klass
                      end),
        foreign_key_name: (if [ActiveRecord::Reflection::HasAndBelongsToManyReflection].include?(reflection.class)
                           reflection.association_foreign_key
                          else
                            reflection.foreign_key
                           end),
        polymorphic_type_field: (if reflection.polymorphic?
                                 reflection.foreign_type
                                 end),
        other_table: other_table,
        table_with_foreign_key: (if [ActiveRecord::Reflection::HasManyReflection,
                                     ActiveRecord::Reflection::HasOneReflection].include?(reflection.class) ||
                                    real_reflection.class == ActiveRecord::Reflection::ThroughReflection
                                 other_table
                                elsif [ActiveRecord::Reflection::BelongsToReflection].include?(reflection.class)
                                  model.table_name
                                elsif [ActiveRecord::Reflection::HasAndBelongsToManyReflection].include?(reflection.class)
                                  reflection.join_table
                                else
                                  :unknown
                                 end),
        foreign_key_points_to: (if [ActiveRecord::Reflection::ThroughReflection].include?(reflection.class)
                                reflection.options[:through].to_s
                               elsif [ActiveRecord::Reflection::HasManyReflection,
                                      ActiveRecord::Reflection::HasOneReflection,
                                      ActiveRecord::Reflection::HasAndBelongsToManyReflection].include?(reflection.class)
                                 model.table_name
                               elsif [ActiveRecord::Reflection::BelongsToReflection].include?(reflection.class)
                                 other_table
                               else
                                 :unknown
                                end),
        reflection_object: real_reflection
      }
    rescue Exception => e
      errors << { model: model,
                  reflection: key,
                  exception: e }
      nil
    end
  end
  { associations: associations.compact,
    errors: errors.compact }
rescue Exception => e
  puts "Could not get foreign keys from #{model}"
  raise
end

MODELS=get_all_models

puts "Building foreign key map..."

FOREIGN_KEY_MAP=MODELS[:models].map do |model|
  [ model,
    get_foreign_keys(model) ]
end.to_h

def find_bad_fk
  FOREIGN_KEY_MAP.each do |k,v|
    begin
      v[:associations].each do |association|
        if association[:table_with_foreign_key] == :unknown
          return k
        end
      end
    rescue Exception => e
      puts "Exception caught: #{e.message}"
      return k
    end
    end
  nil
end

def build_database_map
  db_map = {}
  databases = {}
  FOREIGN_KEY_MAP.each do |klass,hash|
    db_map[klass.table_name] = []
  end
  FOREIGN_KEY_MAP.each do |klass,hash|
    hash[:associations].each do |fk|
      db_map[fk[:table_with_foreign_key]] ||= []
    end
  end
  FOREIGN_KEY_MAP.each do |klass,hash|
    databases[klass.table_name] = klass.connection_config[:makara]["connections"][0]["database"]
    foreign_keys = hash[:associations]
    foreign_keys.each do |fk|
      begin
        db_map[fk[:table_with_foreign_key]] << fk.except(:reflection_object,:other_table,:ruby_name,:association_type,:ruby_class,:table_with_foreign_key)
      rescue Exception => e
        puts "Could not append to table #{fk[:table_with_foreign_key]}"
        raise
      end
    end
  end
  db_map.map do |table_name,foreign_keys|
    {
      table: table_name,
      database: databases[table_name],
      foreign_keys: foreign_keys.uniq
    }
  end
end

def save_database_map(map,filename)
  File.open(filename, "w") do |f|
    f.write map.to_json
  end
end

mark_tables_as_read_write
