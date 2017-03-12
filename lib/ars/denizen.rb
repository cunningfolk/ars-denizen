require "ars/denizen/version"
require "thor"

module Ars
  module Denizen
    class OptionJail
      attr_accessor :options
      def initialize(current_options = {})
        @options = current_options.dup
      end
      def method_missing(meth, *args, &block)
        meth = meth.to_s
        assigner = meth.sub!(/=$/, '')
        meth.freeze
        if assigner
          @options.store(meth, *args)
        else
          @options[meth]
        end
      end
      def respond_to_missing?(name, include_private = false)
        true
      end
    end
    module FileOptions
      module_function
      def load_options(scope, debug = false)
        file = find_options_file(scope)
        return {} unless file
        content = File.binread(file)

        content.gsub!(/^(\s*)(\w+)(\s*\=.*)$/, '\1self.\2\3')
        jail = OptionJail.new
        begin
          jail.instance_eval(content, file)
        rescue StandardError => e
          $stderr.puts("WARNING: unable to load options #{file.inspect}: #{e.message}")
          if debug
            $stderr.puts(*e.backtrace)
          else
            $stderr.puts(e.backtrace.first)
          end
        end
        jail.options
      end
      def find_options_file(scope)
        ars_home = File.expand_path(File.join('~', '.ars'))
        if File.exists? ars_home
          ars_scope = File.join(ars_home, scope.to_s)
          if File.exists? ars_scope
            return ars_scope
          end
        end
      end
    end
    module  ThorGlobber
      module_function
      def glob(globs, exclude_file = nil, *exclude_globs, &block)
        Ars::FileUtil::GlobEnumerator.new.each(globs).match_dot(&block)
      end
    end
    class CLI < Thor
      include Thor::Actions
      include Ars::Denizen::ThorGlobber

      desc 'init', 'initializes you dot files'
      method_option :dotfiles
      method_option :vaultfiles
      def init

        ars_home = File.expand_path(File.join('~', '.ars'))
        unless File.exists? ars_home
          if yes? "Create #{ars_home}?"
            empty_directory ars_home
          else
            abort
          end
        end

        ars_local = File.join(ars_home, 'local')
        unless File.exists? ars_local
          create_file ars_local do
            @dotfiles = ask "Where is your dotfiles repo?"
            out = "dotfiles = '#{@dotfiles}'"
            @vaultfiles = ask "Where is your vaultfiles repo?"
            out << "\nvaultfiles = '#{@vaultfiles}'"
            out
          end
        end

        dot_home = File.expand_path(File.join(options[:dotfiles], 'HOME'))
        unless File.exists? dot_home
          empty_directory dot_home
        end
        home = File.expand_path('~')
        fuzzy = %W{ history ~ }.
                  map{|s| Regexp.new s}
        exact = %W{ .git .ssh .ars .rvm .w3m .viminfo .vagrant.d .Trash}.
                  map{|s| Regexp.new '^' + home + '/' + s + '$'}
        ars_files = [ars_home, File.expand_path(options[:dotfiles]), File.expand_path(options[:vaultfiles])].
                      map{|s| Regexp.new '^' + s + '$' }
        p skip = fuzzy + exact + ars_files
        inside('~/glob_test') do |path|
          glob('*') do |path|
            p path
          end
        end
      end
    end
  end

  module FileUtil
    class GlobEnumerator
      include Enumerable
      attr_reader :file_options
      def initialize(enum=nil)
        @enum = enum
        @file_options = 0
      end

      def each(glob = "*")
        return enum_for(:each, glob) unless block_given?
        Dir.glob(glob, file_options).inject([]) do |files, path|
          files << path
          files << self.class.new.each(path) if File.directory? path
          yield path
          files
        end
      end

      def entries(glob = "*")
        Dir.glob(glob, file_options).map{|file| p file}
      end

      def enum_for(method=:each, *args, &block)
        return self.class.new unless block_given?
        send(method, &block)
      end
      alias :to_enum :enum_for

      def match_dot(*args, &block)
        @file_options |= File::FNM_DOTMATCH
        enum_for(*args, &block)
      end
    end
    class ExcludesFile
      def self.for(exclude_file)
        this = new(exclude_file)
        this.process_file
        this
      end
      def initialize(exclude_file)
        @exclude_file = exclude_file
      end
      def process_file
        globs = File.read(@exclude_file)
        globs.each do |glob|
          case glob
          when %r|^/[*]*/$|
            @top_dirs_glob << glob
          when %r|^/[^*]*/$|
            @top_dirs << glob
          when %r|^/[*]*$|
            @top_files_glob << glob
          when %r|^/[^*]*$|
            @top_files << glob
          when %r|^[*]*/$|
            @dirs_glob << glob
          when %r|^[^*]*/$|
            @dirs << glob
          when %r|^[*]*$|
            @files_glob << glob
          when %r|^[^*]*$|
            @files << glob
          else
            # How?
          end
        end
      end
    end
  end
end
