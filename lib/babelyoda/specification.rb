require 'erb'

require_relative 'specification_loader'

module Babelyoda
	class Specification
		include Babelyoda::SpecificationLoader

    attr_accessor :name
    attr_accessor :development_language
    attr_accessor :localization_languages
    attr_accessor :plain_text_keys
    attr_accessor :engine
    attr_accessor :source_files
    attr_accessor :resources_folder
    attr_accessor :xib_files
    attr_accessor :strings_files
    attr_accessor :scm
    attr_accessor :length_checker_params

    FILENAME = 'Babelfile'

    def self.generate_default_babelfile
      template_file_name = File.join(BABELYODA_PATH, 'templates', 'Babelfile.erb')
      template = File.read(template_file_name)
      File.open(FILENAME, "w+") do |f|
        f.write(ERB.new(template).result())
      end
    end

    def self.load
      trace_spec = @spec.nil? && ::Rake.application.options.trace
	    @spec ||= load_from_file(filename = FILENAME)
      if @spec
        @spec.plain_text_keys = true if @spec.plain_text_keys.nil?
        @spec.dump if trace_spec && @spec
      end
	    return @spec
    end

    def all_languages
      [ development_language, localization_languages].flatten!
    end
  end
end
