def walk_directory(directory='.', include_directories: false, &block)
  if directory[-1] != '/'
    directory =  directory + '/'
  end
  directories = []
  Dir.entries(directory).each do |entry|
    next if ['.','..'].include? entry
    if (!File.directory?(directory + entry)) || include_directories
      block.call(directory + entry)
    end
    if File.directory?(directory+entry)
      directories << directory+entry
    end
  end
  directories.each do |dir|
    walk_directory(dir + '/', include_directories: include_directories, &block)
  end
  nil
end

def force_load(directory)
  failures = []
  walk_directory(directory) do |file|
    next unless file =~ /\.rb$/
    puts "Loading #{file}"
    begin
      gem_original_require file
    rescue Exception => e
      failures << [file,e]
    end
  end
  failures.compact
end

def force_load_all_models(directory="#{ENV['HOME']}/carrot")
  failures = []
  walk_directory(directory, include_directories: true) do |file|
    next unless file =~ /models$/ && File.directory?(file)
    MagicMirror.with_temp_wd(file) do
      failures += force_load(file).compact.map do |source_file, exception|
        { working_directory: file,
          file: source_file,
          exception: exception }
      end
    end
  end
  failures
end

def force_load_from_path(path=$LOAD_PATH)
  oldwd=Dir.getwd
  path.flat_map do |dir|
    next unless dir =~ /carrot/
    puts "Loading from #{dir}"
    begin
      Dir.chdir dir
    rescue => e
      next
    end
    force_load(dir).map do |failed_file,exception|
      { working_directory: dir,
        file: failed_file,
        exception: exception }
    end.compact
  end.compact
ensure
  Dir.chdir oldwd
end

def exception_location(exn)
  file,line_string=exn.backtrace[0].split(':')[0..1]
  [file,line_string.to_i]
end

def class_at_exception(exn)
  MagicMirror.class_at(*exception_location(exn))
end

def still_missing?(name_error_exception)
  missing_class = name_error_exception.to_s.split(' ').last
  begin
    MagicMirror.eval_at(*exception_location(name_error_exception), missing_class)
    false
  rescue NameError => e
    missing_now = e.to_s.split(' ').last
    if missing_now != missing_class
      raise
    end
  end
end

def resolve_dependencies(force_load_errors)
  loop do
    fixed_one=false
    force_load_errors = force_load_errors.map do |hash|
      begin
        if hash[:exception].is_a? NameError
          if !still_missing?(hash[:exception])
            MagicMirror.with_temp_wd(hash[:working_directory]) do
              load hash[:file]
              fixed_one=true
            end
          end
        end
        nil
      rescue Exception => e
        hash[:exception] = e
        hash
      end
    end.compact
    break unless fixed_one
  end
  force_load_errors
end
