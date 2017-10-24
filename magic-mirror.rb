begin
  Rails
  raise "MagicMirror is loading after Rails. This is no good."
rescue NameError
  nil
end

require 'socket'
class MagicMirror
  attr_reader :successful_loads
  @successful_loads = {}
  @failed_loads = []
  @in_require = 0
  @inferred_nesting = []
  def self.inferred_nesting
    @inferred_nesting
  end
  def self.push_nesting(klass)
    @inferred_nesting.push(klass)
  end
  def self.pop_nesting
    @inferred_nesting.pop
  end
  def self.report_loaded_file(file)
    @successful_loads[file] = true
  end
  def self.with_temp_wd(wd)
    oldwd = Dir.getwd
    Dir.chdir(wd)
    yield
  ensure
    Dir.chdir(oldwd)
  end
  def self.failed_loads
    @failed_loads
  end
  def self.failed_loads=(new_value)
    @failed_loads=new_value
  end
  def self.in_require=(new_value)
    @in_require=new_value
  end
  def self.in_require
    @in_require
  end
  def self.retry_failed_loads
    @failed_loads -= @failed_loads.select do |directory,file|
      with_temp_wd(directory) do
        begin
          puts "Up-front autoloading: #{file} from #{directory}"
          require(file)
          true
        rescue NameError => e
          puts "Warning: NameError #{e.message}\n\n#{e.backtrace.join("\n")}"
          nil
        end
      end
    end
  end
end

class Method
  alias :magic_mirror_real_source_location :source_location
  def source_location
    loc = magic_mirror_real_source_location
    return loc unless loc
    file,line = loc
    [file.sub(MagicMirror.virtual_path, ''), line]
  end
end

class UnboundMethod
  alias :magic_mirror_real_source_location :source_location
  def source_location
    loc = magic_mirror_real_source_location
    return loc unless loc
    file,line = loc
    [file.sub(MagicMirror.virtual_path, ''), line]
  end
end

class Module
  attr_reader :magic_mirror_source_locations
  attr_reader :source_locations
  attr_reader :module_included_by
  alias :magic_mirror_real_append_features :append_features
  def append_features(other_mod)
    MagicMirror.add_includer(self,other_mod)
    magic_mirror_real_append_features(other_mod)
  end
  #alias :magic_mirror_real_autoload :autoload
  def dont_autoload(const_name, path)
    unless Kernel.instance_method(:require).source_location
      raise "MagicMirror require has been thwarted!"
    end
    MagicMirror.failed_loads << [Dir.getwd, path]
    magic_mirror_real_autoload const_name, path
  end
end

module NotKernel
  alias :magic_mirror_real_require :require
  class << self
    alias :magic_mirror_real_private_method_defined? :private_method_defined?
    def private_method_defined?(method)
      if method.to_sym == :gem_original_require
        false
      else
        magic_mirror_real_private_method_defined? method
      end
    end
  end

  def require(path)
    MagicMirror.in_require += 1
    puts "Loading #{path} at depth #{MagicMirror.in_require}"
    ret=begin
          magic_mirror_real_require(path)
        rescue Gem::LoadError
          gem_original_require(path)
        end
    if Kernel.instance_method(:require).source_location
      puts "Loaded #{path} at depth #{MagicMirror.in_require}"
    else
      raise "MagicMirror require overridden by #{path}"
    end
    ret
  ensure
    MagicMirror.in_require -= 1
    if MagicMirror.in_require == 0
      puts "Reached depth 0 after loading #{path}"
      puts "Require is #{Kernel.instance_method(:require).source_location}"
      MagicMirror.in_require = 1
      begin
        MagicMirror.retry_failed_loads
      ensure
        MagicMirror.in_require = 0
      end
    end
  end
end


class Class
  attr_reader :source_locations
  attr_reader :magic_mirror_source_locations
end

def filter_symbols(regex,symbols,prefix)
  symbols.select do |symb|
    symb.class == Symbol
  end.map(&:to_s).select do |meth|
    regex =~ meth
  end.map do |meth|
    "#{prefix}#{meth}"
  end
end


# ActiveRecord::Fixtures really fucks with this method!

# This is a naive apropos function that works in a similar manner to Pry's
# introspection commands. It starts at Object, gets all the methods and
# constants, and then iterates through the nested classes found in the
# constants.
#
# The reason this doesn't work is that some classes override their
# :methods, :constants, and :instance_methods methods. The apropos
# in MagicMirror is better because it gets a chance to call these methods
# before they get overridden.

def naive_apropos(regex, accept: [:class, :module, :method], klass: Object,seen: [])
  seen << klass
  filter_symbols(regex,klass.methods,"#{klass}.").each do |match|
    puts match
  end
  filter_symbols(regex,klass.instance_methods,"#{klass}#").each do |match|
    puts match
  end
  filter_symbols(regex,klass.constants,"#{klass}::").each do |match|
    puts match
  end
  klass.constants.each do |const_name|
    const = klass.const_get(const_name)
    if const.respond_to?(:methods) && const.respond_to?(:instance_methods) && const.respond_to?(:constants) &&
       const != Object && !seen.include?(const)
      apropos(regex, accept: accept, klass: const, seen: seen)
    end
  end
rescue => e
  puts "Error while searching through #{klass}"
  raise
end

class MutexedMagicMirror
  def self.method_missing(name, *args)
    MagicMirror.with_mutex do
      MagicMirror.send(name, *args)
    end
  end
end

# Presentations

# Presentations were a feature of the Dynamic Windows system on the Symbolics Lisp Machine.
# They allow all data on the screen to retain a link to the in-memory objects they were
# taken from. This was combined with a universal Command Table system, which was integrated
# with the GUI.
#
# SLIME includes a crude attempt to implement presentations within its REPL. Anything
# displayed in red text can be copied and pasted into new Lisp code at the REPL, which
# can access the underlying objects. So you can do something like this:
#
# SLIME> (defvar *foobar* (make-hash-table :test 'equalp))
# #<HASH 0x38384d>
# ;; Copy the HASH above to the REPL
# SLIME> (setf (gethash #<HASH 0x38384d> 'foo) 'bar)
# BAR
# SLIME> (gethash *foobar* 'foo)
# BAR
# SLIME>
#
# You can also right-click on the red text and choose the Inspect option from
# the context menu. This launches an interactive object inspector.
#
# That is about the extent of what SLIME can do with presentations, and perhaps the extent of
# what it makes sense to do if you're not going to implement the GUI system and the command tables,
# perhaps with a few exceptions.
#
# One use-case that I think it's important to support in Ruby MagicMirror is to have the output of
# MagicMirror.apropos be clickable in EMACS. Clicking an apropos result should cause that class, module,
# or method to be opened in EMACS.
#
# An easy way to implement this would be to have MagicMirror specify a JavaScript-style on-click callback.
# The callback would be an Emacs Lisp function which would be passed the Emacs-side presentation object
# to do something with.
#
# The neat trick would be allowing any Ruby method to return an object that would automatically have
# a callback in Emacs, without having to explicitly tell MagicMirror to add it.
#
# SLIME presentations are weak references, so sometimes expressions involving them fail because the
# underlying objects got garbage collected.
#
# Implementing them requires that EMACS be given unique identifiers for each object sent to it for
# display. Ruby provides the .object_id method, which is suitable for this purpose. MagicMirror could
# store all returned objects in a hash, where the object_id is the key. These would be strong references,
# which would eliminate the problem of presentations getting GC'd.
#
# Emacs would have to keep track of which presentations still existed (either in the REPL or a source buffer),
# so it could tell MagicMirror when it can remove objects from the hash table. Some kind of reference-counting system
# would be the easiest to implement.
#

class MagicMirror
  @reverse_lookup_index = {}
  @apropos = {}
  @class_apropos = {}
  @last_known_class_methods = {}
  @last_known_class_instance_methods = {}
  @last_known_class_constants = {}
  @module_includers = {}
  @defined_by_magic_mirror = {}
  @in_eval_at = false
  @mutex = Object::Mutex.new

  def self.mutexed
    MutexedMagicMirror
  end

  def self.add_includer(mod,includer)
    @module_includers[mod] ||= []
    @module_includers[mod] << includer
  end

  def self.included_by(mod)
    @module_includers[mod]
  end

  def self.with_mutex
    @mutex.lock
    yield
  ensure
    @mutex.unlock
  end

  def self.virtual_path
    my_pid=$$
    "/tmp/magic-mirror-sources.#{my_pid}"
  end

  def self.dir_butlast(path)
    path.split('/')[0..-2].join('/')
  end

  def self.make_directory_chain(full_path)
    if Dir.exists?(full_path)
      true
    else
      make_directory_chain(dir_butlast(full_path))
      Dir.mkdir full_path
      true
    end
  end

  def self.make_virtual_dir(real_path)
    make_directory_chain "#{virtual_path}/#{real_path}"
    "#{virtual_path}/#{real_path}"
  end

  def self.get_real_path(path)
    if path[0..virtual_path.length-1] == virtual_path
      path[virtual_path.length..-1]
    else
      path
    end
  end

  def self.write_to_virtual_file(real_path, data)
    make_virtual_dir(dir_butlast(real_path))
    File.open "#{virtual_path}/#{real_path}", "w" do |f|
      f.write data
    end
    "#{virtual_path}/#{real_path}"
  end

  def self.with_data_in_file(real_path, data)
    virtual_path = write_to_virtual_file(real_path, data)
    yield virtual_path
    # TODO: Delete the file and associated directories.
  end

  def self.eval_in_file(real_path, expr, line: 1)
    (line-1).times do
      expr = "\n" + expr
    end
    with_data_in_file(real_path, expr) do |virtual_path|
      load virtual_path
    end
  end

  def self.class_opening(klass)
    if klass.class == Class
      "class"
    elsif klass.class == Module
      "module"
    else
      raise "Constant #{full_class_name(klass)} is neither class nor module"
    end
  end

  def self.build_class_opening(nesting)
    nesting.reverse.map do |klass|
      "#{class_opening(klass)} ::#{full_class_name(klass)}"
    end.join(';') + ";"
  end

  def self.build_class_closing(nesting)
    nesting.map do |klass| "end" end.join(';')
  end

  def self.eval_at(file, line, expr)
    nesting = nesting_at(file,line)
    opening = (nesting && build_class_opening(nesting)) || ""
    closing = (nesting && build_class_closing(nesting)) || ""
    eval_in_file(file, %{ #{opening} ::Thread.current[:magic_mirror_eval_at_result]=#{expr}; #{closing}}, line: line)
    Thread.current[:magic_mirror_eval_at_result]
  end

  def self.dumb_eval_at(file, line, expr)
    # Evaluates EXPR in the class that would contain an expression
    # at the given file and line number, without doing anything to ensure that
    # methods defined by EXPR will have reasonable source_locations.
    #
    # eval_at is the smart version that takes the extra trouble.
    @in_eval_at = [file, line]
    c = class_at(file,line)
    if c.is_a? Module
      c.module_eval(expr)
    elsif c.is_a? Module
      c.class_eval(expr)
    else
      Object.class_eval(expr)
    end
  ensure
    @in_eval_at = false
  end

  def self.register_class(klass,outer=nil)
    @class_apropos[klass] = outer || klass
  end
  def self.add_class_definition_range(klass, nesting, start_loc,end_loc)
    filename,start_line = start_loc
    end_line = end_loc[1]
    @reverse_lookup_index[filename] ||= {}
    @reverse_lookup_index[filename][start_line] = { class: klass,
                                                    length: end_line-start_line,
                                                    nesting: nesting }
  end
  def self.seen_file?(filename)
    !!@reverse_lookup_index[filename]
  end
  def self.info_at(filename, line)
    @reverse_lookup_index[filename] &&
    @reverse_lookup_index[filename].each do |start_line,info|
      if line >= start_line && line <= start_line+info[:length]
        return info
      end
    end
    nil
  end
  def self.class_at(filename, line)
    info = info_at(filename, line)
    info && info[:class]
  end
  def self.nesting_at(filename, line)
    info = info_at(filename, line)
    info && info[:nesting]
  end
  def self.update_apropos_entry(entry, new_def)
    entry[new_def[:class]] = new_def
    entry
  end
  def self.update_methods_for_class(klass,methods,method_type)
    methods &&
    methods.each do |meth|
      next unless meth.class == Symbol
      @apropos[meth.to_s] ||= {}
      filename,line = method_type == :class ?
                        klass.method(meth).source_location :
                        klass.instance_method(meth).source_location
      update_apropos_entry(@apropos[meth.to_s], { class: klass, type: method_type, inherited: class_at(filename,line) != klass,
                                                  filename: filename, line: line })
    end
    nil
  rescue ArgumentError
    puts "MagicMirror WARNING: Class #{klass} patches one or more of the methods 'instance_method' or 'method'."
    puts "MagicMirror WARNING: Unable to collect method-location information for #{klass}"
  end
  def self.get_methods(klass,type)
    case type
    when :class
      klass.methods + klass.private_methods
    when :instance
      klass.instance_methods + klass.private_instance_methods
    end
  end
  $total_constants = 0
  def self.update_apropos(klass)
    return unless klass
    if @last_known_class_methods[klass] != klass.methods
      update_methods_for_class(klass,get_methods(klass,:class),:class)
      @last_known_class_methods[klass] = klass.methods
    end
    if @last_known_class_instance_methods[klass] != klass.instance_methods
      update_methods_for_class(klass,get_methods(klass,:instance),:instance)
      @last_known_class_instance_methods[klass] = klass.instance_methods
    end
    if @last_known_class_constants[klass] != klass.constants
      klass.constants.each do |const|
        register_class const,klass
      end
      @last_known_class_constants[klass] = klass.constants
    end
  end
  def self.fqmn(klass,name,type)
    separator = if type == :class
                  '.'
                else
                  '#'
                end
    "#{klass}#{separator}#{name}"
  end
  def self.apropos_entry_strings(name, entry, include_inherited)
    result=[]
    entry.each do |klass,definition|
      next if !include_inherited && definition[:inherited]
      result << fqmn(klass,name,definition[:type])
    end
    result
  end
  def self.render_class_name(klass,outer)
    if klass == outer
      "#{klass}"
    else
      "#{outer}::#{klass}"
    end
  end
  def self.full_class_name(klass)
    render_class_name(klass,@class_apropos[klass])
  end
  def self.apropos_data(regex,include_inherited: false, match_classes: true, match_methods: true)
    results = []
    if match_classes
      @class_apropos.each do |klass,outer|
        class_name = render_class_name(klass,outer)
        if regex =~ class_name
          results << class_name
        end
      end
    end
    if match_methods
      @apropos.each do |method_name, entry|
        apropos_entry_strings(method_name, entry, include_inherited).each do |fqmn|
          if regex =~ fqmn
            results << fqmn
          end
        end
      end
    end
    results
  end
  def self.apropos(regex,include_inherited: false, match_classes: true, match_methods: true)
    apropos_data(regex, include_inherited: include_inherited,
                 match_classes: match_classes, match_methods: match_methods).each do |datum|
      puts datum
    end
    nil
  end
end

TracePoint.new(:class,:end) do |tp|
  tp.self.module_eval do
    next if self.frozen?
    next if /^#/ =~ self.to_s
    case tp.event
    when :class
      MagicMirror.with_mutex do
        MagicMirror.register_class(self)
        MagicMirror.push_nesting(self)
        MagicMirror.report_loaded_file(tp.path)
      end
      @magic_mirror_last_begin = [tp.path, tp.lineno]
      @source_locations ||= []
      @source_locations << @magic_mirror_last_begin
    when :end
      if @magic_mirror_last_begin.nil?
      else
        @magic_mirror_source_locations ||= []
        @magic_mirror_source_locations << { begin: @magic_mirror_last_begin,
                                     end: [tp.path, tp.lineno],
                                     nesting: MagicMirror.inferred_nesting.reverse }
        MagicMirror.with_mutex do
          MagicMirror.add_class_definition_range(self, MagicMirror.inferred_nesting.reverse, @magic_mirror_last_begin, [tp.path, tp.lineno])
          MagicMirror.update_apropos(self)
          MagicMirror.pop_nesting
        end
      end
    end
  end
end.enable


require 'ripper'

# FIXME: In Ruby, $stdin, $stdout, and $stderr and their associated constants
#        are generated from scratch on a per-thread basis. They are not copied
#        from the main thread's values, but rather are attached directly to
#        the underlying Unix fd's 0, 1, and 2.
#
#        This presents a serious problem, because we want threads that are
#        created from SRIME to have $stdin/$stdout/$stderr that are redirected
#        to the socket, just like the main MagicMirror server thread.
#
#        The MagicMirror@multiplexed_streams are meant as a solution to a similar
#        problem, but the wrong one. Multiplexed streams would be useful if
#        $stdin, $stdout, and $stderr were global variables whose values
#        cut across threads.
#
#        Instead, we must abandon multiplexed streams. Instead, new threads
#        created by threads that are attached to SRIME should have STDIO objects
#        that are also attached to SRIME. while threads created elsewhere
#        (eg, from the main thread) should continue to have Ruby's default
#        behavior.


class Thread
  class << self
    alias :magic_mirror_real_new :new
    def new(*args, &block)
      parent_stdin=$stdin.dup
      parent_stdout=$stdout.dup
      parent_stderr=$stderr.dup
      MagicMirror.with_redirected_streams([$stdin,$stdout,$stderr],
                                    [parent_stdin,parent_stdout,parent_stderr]) do
        magic_mirror_real_new(*args, &block)
      end
    ensure
      parent_stdin.close
      parent_stdout.close
      parent_stderr.close
    end
  end
end

class MagicMirror
  def self.with_redirected_streams(original_streams, new_streams)
    restores=[]
    original_streams.zip(new_streams).each do |original_stream,new_stream|
      restores << original_stream.dup
      original_stream.reopen new_stream
    end
    yield
  ensure
    original_streams.zip(restores) do |original_stream,restore|
      original_stream.reopen restore
    end
  end
  class Server
    def ripper_sexp_to_lisp(sexp)
      if sexp.is_a?(Array)

        '(' + (sexp.map do |elem|
                 ripper_sexp_to_lisp(elem)
               end.join(' ')) + ')'
      elsif sexp.is_a?(Symbol) || sexp.is_a?(Numeric)
        sexp.to_s
      elsif sexp.is_a?(String)
        '"' + sexp + '"'
      elsif sexp.is_a?(FalseClass)
        "nil"
      elsif sexp.is_a?(TrueClass)
        "t"
      elsif sexp.is_a?(NilClass)
        "nil"
      else
        raise "Unable to translate a #{sexp.class} to Emacs Lisp."
      end
    end

    def parse_ruby_to_lisp(ruby_text)
      ripper_sexp_to_lisp(Ripper.sexp ruby_text)
    end

    def read_command(sock)

    end

    def handle_client(sock)
      Thread.new do
        # TODO: Forward STDIN and STDOUT to sockets.
        # TODO: Full-duplex interaction.
        # TODO: Accept commands from EMACS.
        # TODO: Connect to this from EMACS.
        # TODO: Implement a command to relay an interrupt from EMACS
        # TODO: Figure out how byebug works and implement something like it here.
        # TODO: Implement presentations
        # TODO: Make MagicMirror.apropos return presentations that when clicked, cause
        #       EMACS to open the source file where the class or method is defined.
        loop do
        end
      end
    end

    def initialize(socket_path: "/tmp/ruby-magic-mirror.sock")
      Thread.new do
        listener=UNIXServer.new socket_path
        loop do
          handle_client(listener.accept)
        end
      end
    end

  end
end
