require 'builder'
require 'net/http'
require 'nokogiri'
require 'stringio'

require 'babelyoda/specification_loader'

module Babelyoda
  class Keyset 
    def to_xml(xml, language = nil)
      xml.keyset(:id => name) do
        keys.each_value do |key|
          xml.key(:id => key.id, :is_plural => 'False') do
            xml.context(key.context)
            key.values.each_value do |value|
              next if language && (value.language.to_s != language.to_s)
              xml.value(value.text, :language => value.language, :status => value.status)
            end
          end
        end
      end
    end
    
    def self.parse_xml(node)
      result = self.new(node[:id])
      node.css('key').each do |key_node|
        result.merge_key!(Babelyoda::LocalizationKey.parse_xml(key_node))
      end
      result
    end
  end

  class LocalizationKey 
    def self.parse_xml(node)
      context = node.css('context').first
      context &&= context.text
      result = self.new(node[:id], context)
      node.css('value').each do |value_node|
        value = Babelyoda::LocalizationValue.parse_xml(value_node)
        result << value if value
      end
      result
    end
  end
  
  class LocalizationValue
    def self.parse_xml(node)
      if node.text.length > 0
        self.new(node[:language], node.text, node[:status])
      end
    end
  end
  
	class Tanker
		include Babelyoda::SpecificationLoader
		
		class FileNameInvalidError < RuntimeError ; end

    attr_accessor :endpoint
    attr_accessor :token
    attr_accessor :project_id

    def replace(keyset, language = nil)
      doc = project_xml do |xml|
        keyset.to_xml(xml, language)
      end
      payload = { 
        :file => StringIO.new(doc),
        'project-id' => project_id,
        'keyset-id' => keyset.name,
        :format => 'xml'
      }
      payload.merge!({:language => language}) if language
      post('/keysets/replace/', payload)
    end
    
    def list
      get('/keysets/', { 'project-id' => project_id }).css('keyset').map { |keyset| keyset['id'] }
    end
    
    def create(keyset_name)
      post('/keysets/create/', { 'project-id' => project_id, 'keyset-id' => keyset_name })
    end
    
    def export(keyset_name = nil, languages = nil, status = nil, safe = false)
      payload = { 'project-id' => project_id }
      payload.merge!({ 'keyset-id' => keyset_name }) if keyset_name
      if languages
        value = languages
        value = languages.join(',') if languages.respond_to?(:join)
        payload.merge!({ 'language' => value })
      end
      payload.merge!({ 'status' => status.to_s }) if status
      payload.merge!({ 'safe' => safe }) if safe
      get('/projects/export/xml/', payload)
    end
    
    def load_keyset(keyset_name, languages = nil, status = nil, safe = false)
      doc = export(keyset_name, languages, status, safe)
      doc.css("keyset[@id='#{keyset_name}']").each do |keyset_node|
        keyset = Babelyoda::Keyset.parse_xml(keyset_node)
        return keyset if keyset.name == keyset_name
      end
      Babelyoda::Keyset.new(keyset_name)
    end
    
    def drop_keyset!(keyset_name)
      delete("/admin/project/#{project_id}/keyset/", { :keyset => keyset_name })
    end
    
  private
  
    MULTIPART_BOUNDARY = '114YANDEXTANKERCLIENTBNDR';

    def multipart_content_type
      "multipart/form-data; boundary=#{MULTIPART_BOUNDARY}"
    end

    def method(name)
      "#{endpoint}#{name}"
    end

    def project_xml(&block)
      xml = Builder::XmlMarkup.new
      xml.instruct!(:xml, :encoding => "UTF-8")
      xml.tanker do
        xml.project(:id => project_id) do
          yield xml
        end
      end
    end

    def multipart_data(payload = {}, boundary = MULTIPART_BOUNDARY)
      payload.keys.map { |k|
        "--#{boundary}\r\n" + multipart_field(k, payload[k])
      }.join('') + "--#{boundary}--\r\n"
    end

    def multipart_field(k, v)
      if v.respond_to?(:read)
        "Content-Disposition: form-data; name=\"#{k}\"; filename=\"#{k}.xml\"\r\n" +
        "Content-Type: application/octet-stream\r\n" +
        "Content-Transfer-Encoding: binary\r\n\r\n" +
        "#{v.read}\r\n"
      else
        "Content-Disposition: form-data; name=\"#{k}\"\r\n\r\n" +
        "#{v}\r\n"
      end
    end

    def post(method_name, payload)
      uri = URI(method(method_name))
      req = Net::HTTP::Post.new(uri.path)
      req['AUTHORIZATION'] = token
      req.content_type = multipart_content_type
      req.body = multipart_data(payload)

      # puts "POST URI: #{uri}"
      # puts "POST BODY: #{req.body}"

      res = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end
      
      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        Nokogiri::XML.parse(res.body)
      else
        doc = Nokogiri::XML.parse(res.body)
        error = doc.css('result error')[0].content
        raise RuntimeError.new(error)
      end
    end

    def get(method_name, payload = nil)
      uri = URI(method(method_name))
      uri.query = URI.encode_www_form(payload) if payload
      req = Net::HTTP::Get.new(uri.request_uri)
      req['AUTHORIZATION'] = token

      # puts "GET URI: #{uri}"

      res = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end

      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        Nokogiri::XML.parse(res.body)
      else
        doc = Nokogiri::XML.parse(res.body)
        error = doc.css('result error')[0].content
        raise Error.new(error)
      end
    end
    
    def delete(method_name, payload = nil)
      uri = URI(method(method_name))
      uri.query = URI.encode_www_form(payload) if payload
      req = Net::HTTP::Delete.new(uri.request_uri)
      req['AUTHORIZATION'] = token

      # puts "DELETE URI: #{uri}"

      res = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end

      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        Nokogiri::XML.parse(res.body)
      else
        doc = Nokogiri::XML.parse(res.body)
        puts "DOC: #{doc}"
        error = doc.css('result error')[0].content
        raise Error.new(error)
      end
    end
	end
end