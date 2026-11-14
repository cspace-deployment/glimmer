# frozen_string_literal: true

module ApplicationHelper

  ### begin search output methods ###

   # TODO: DRY
  def requery_solr(params,fields_to_export,summary_field=nil,map=nil)
    requery_url, solr_params = format_requery_params(params)
    filepath = get_paginated_solr_results(requery_url,solr_params,fields_to_export)
  end

  def requery_solr_summarize(params,fields_to_export,summary_field,map=nil)
    requery_url, solr_params = format_requery_params(params)
    summary_field, fields_to_export, summary_database_path = get_paginated_solr_results(requery_url,solr_params,fields_to_export,summary_field=summary_field)
    return summary_field, fields_to_export, summary_database_path
  end

  def requery_solr_map(params,fields_to_export=nil,summary_field=nil,map=true)
    # puts fields_to_export.class
    requery_url, solr_params = format_requery_params(params)
    map_tsv_path = get_paginated_solr_results(requery_url,solr_params,fields_to_export,summary_field,map)
    return map_tsv_path
  end

  def format_requery_params(blacklight_q_params)
    puts "hello "*100
    puts blacklight_q_params
    solr_params = {}
    if blacklight_q_params.key?("search_field")
      if blacklight_q_params["search_field"] == "advanced"
        blacklight_q_params.except("f","search_field").each do |k,v|
          solr_params.merge!({k => "'#{v}'"})
          solr_params&.delete("advanced")
        end
      end
      # puts blacklight_q_params["search_field"], blacklight_q_params["q"] 
      # if blacklight_q_params["search_field"].kind_of? Hash || blacklight_q_params["search_field"] == "text"
      solr_params[blacklight_q_params["search_field"]] = blacklight_q_params["q"]
      solr_params.delete("search_field")
      solr_params.delete("q")
      # end
    end

    if blacklight_q_params.key?("range")
      blacklight_q_params['range'].each do |k,v|
        value="[#{v['begin']} TO #{v['end']}]"
        solr_params.merge!({k => value})
      end
    end

    if blacklight_q_params.key?("f")
      # puts blacklight_q_params['f']
      if blacklight_q_params['f'].key?("Has image")
        
        if blacklight_q_params['f']["Has image"][0] == "has_image"
          solr_params.merge!({"blob_ss" => "[* TO *]"})
        elsif blacklight_q_params['f']["Has image"][0] == "no_image"
          solr_params.merge!({"-(blob_ss" => "[* TO *])"})
        end
        blacklight_q_params['f'] = blacklight_q_params['f'].delete("Has Image")

      end
      # puts solr_params
      blacklight_q_params['f']&.each do |k,v|
        if v.kind_of?(Array)
          if k.end_with?("_ss")
            v = v.join(separator = '" "' )
          end 
        else
            v = v.join(separator = " ")
          end
        solr_params.merge!({k => "'#{v}'"})
      end
      solr_params.delete('f')
    end
    solr_params&.delete("advanced")
    # puts solr_params


    endpoint_params = ""
    solr_params.each do |k,v|
      endpoint_params+="#{k} : #{v} "
    end
    solr_url = Rails.application.config.blacklight_solr['url'].to_s
    url_string = solr_url+"/select?defType=edismax&df=text&q.op=AND&q=#{endpoint_params}"
    url_string = url_string.gsub("'","%22").gsub(" ","%20")
    puts url_string
    
    return url_string, solr_params
  end

  def get_paginated_solr_results requery_url, solr_params, fields_to_export, summary_field=nil, map=nil
    # TODO this method is crazy sprawling, refactor & DRY
    require 'uri'
    require 'net/http'
    require 'json'
    require 'thread'
    require 'securerandom'
    require 'csv'


    fields_to_export = JSON.parse(fields_to_export)
    headers = []

    if map.nil?
      first_row = fields_to_export.map { |value| "" }
      query_params_readable = solr_params.map { |k,v| 
        "#{Rails.application.config.csv_output_fields[k]} : #{v}"
      }
      query_params_readable = query_params_readable.join("\n")
      first_row = first_row.unshift(query_params_readable)
      headers = headers.unshift("Query parameters")
      fields_to_export.each do |item|
        headers << Rails.application.config.csv_output_fields[item]
      end
    else
      # puts fields_to_export
      # puts Rails.application.config.mapping_fields

      fields_to_export.each do |k,v|
        # puts v
        unless k == "objfcpgeoloc_p"
          headers << v
        end
      end
      headers = headers + ["DecimalLatitude","DecimalLongitude"]
      # puts headers
    end


    # define the number of results per page returned by solr
    # this is a guess at a reasonable number without overloading the server? 
    # it could be too low though, esp for large result sets
    results_per_page = 10000
    requery_url_string = "#{requery_url}&rows=#{results_per_page}"
    puts requery_url_string
    response = get_single_solr_page(requery_url_string,0)
    
    begin
      total_items = JSON.parse(response.body)['response']['numFound'].to_i
    rescue
      puts JSON.parse(response.body)['response']['numFound'].to_i
      path = 'public/error_'+SecureRandom.uuid+'.html'
      File.write(path, response.body+response.each_header.to_h.to_s)
      return path
    end
    number_of_full_pages, last_page_num_items = total_items.divmod(results_per_page)
    starting_row = 0
    last_page = number_of_full_pages + 1
    last_page_start_row = (number_of_full_pages*results_per_page)
    last_row = total_items - 1

    uuid = SecureRandom.uuid[0..7]

    page_queue = Queue.new
    (0..last_page_start_row).step(results_per_page) do |start_row|
      page_queue << start_row
    end

    if map != nil
      require 'time'
      map_tsv_filepath = "public/mapper_#{Time.current.localtime.strftime("%Y-%m-%d_%H-%M-%S")}.tsv"
      # puts headers.to_s
      # puts fields_to_export.to_s

      counter = 0
      mappable = []

      CSV.open(map_tsv_filepath, "a", **{ :col_sep => "\t" }) do |csv|
        csv << headers

        workers = last_page.times.map do
          Thread.new do
            until page_queue.empty?
              start_row = page_queue.pop(true) rescue nil
              if start_row
                response = get_single_solr_page(requery_url_string,start_row)
                JSON.parse(response.body)['response']['docs'].each do |row|
                  row_to_enter = []
                  temp = {}

                  if counter < 2000
                    identifier = Rails.application.config.mapping_fields["identifier"][0]
                    temp[row[identifier]] = {}

                    Rails.application.config.mapping_fields.each do |field,value|
                      # temp[Rails.application.config.mapping_fields["identifier"].collect {|k| k }]
                      unless field == "identifier" 
                        if row[field].present?
                          temp[row[identifier]][value] = row[field]
                        end
                      end



                    end
                    puts temp.class
                    mappable << temp.to_h
                  else
                    break
                  end

                  counter += 1
                end
              end
            end
          end
        end
        workers.each(&:join)
      end

      return mappable #map_tsv_filepath
    end

    if summary_field != nil
      summary_database, summary_database_path = create_summary_db(fields_to_export,summary_field,uuid)
      # puts fields_to_export.insert(0,"count")
      columns = "#{summary_field}_summary, #{fields_to_export.insert(0,"count").join(", ")}"
      # puts columns
      # number of columns doesn't include the "count" column
      number_of_columns = fields_to_export.length()
      parameterized_values = "?"
      number_of_columns.times { parameterized_values += ", ?" }
      
      workers = last_page.times.map do
        Thread.new do
          until page_queue.empty?
            start_row = page_queue.pop(true) rescue nil
            if start_row
              response = get_single_solr_page(requery_url_string,start_row)
              # puts JSON.parse(response.body)['response']['docs']
              JSON.parse(response.body)['response']['docs']&.each do |row|
                if row[summary_field].nil?
                    row[summary_field] = ""
                  end
                if row[summary_field].is_a?(Array)
                  values = [row[summary_field].join(separator = " > ")]
                else
                  values = [row[summary_field]]
                end
                # puts values.to_s
                fields_to_export.each do |column|

                  if row[column].is_a?(Array)
                    # puts row[column].join(separator = " > ")
                    values << row[column].join(separator = " | ")
                  else
                    values << row[column]
                  end
                end
                # puts values.to_s

                insert_string = "INSERT INTO summary (#{columns}) VALUES (#{parameterized_values});"
                # puts insert_string
                summary_database.execute insert_string, values

              end
            end
          end
        end
      end
      workers.each(&:join)

      return summary_field, fields_to_export, summary_database_path

    end

   
    uuid = SecureRandom.uuid[0..7]
    results_filepath = "public/query_results_#{uuid}.csv"

    CSV.open(results_filepath, "a") do |csv|
      csv << headers
      csv << first_row

      workers = last_page.times.map do
        Thread.new do
          until page_queue.empty?
            start_row = page_queue.pop(true) rescue nil
            if start_row
              response = get_single_solr_page(requery_url_string,start_row)
              JSON.parse(response.body)['response']['docs'].each do |row|
                # account for the column for search params
                row_to_enter = [""]
                fields_to_export.each do |field|
                  row_to_enter << row[field]
                end
                csv << row_to_enter
              end
            end
          end
        end
      end
      workers.each(&:join)
    end

    return results_filepath
  end

  def make_map_data mappable
    mappable_array = []
    mappable.each do | item |
      item.each do | objmusno_txt, metadata |
        puts item
        reformatted_item = {}
        if metadata["Lat/long"].nil?
          puts "NOT MAPPABLE"
        else
          reformatted_item["Latitude"] = metadata["Lat/long"].split(",").map(&:to_f)[0]
          reformatted_item["Longitude"] = metadata["Lat/long"].split(",").map(&:to_f)[1]
          reformatted_item["Museum number"] = objmusno_txt
          reformatted_item["Object name"] = metadata["Object name"]
          reformatted_item["Collection place"] = metadata["Collection place"]
          reformatted_item["Culture hierarchy"] = metadata["Culture hierarchy"]&.join(" / ")

          mappable_array << reformatted_item
        end
      end
    end 
    # limiting the number of items that can be mapped so it doesn't get overloaded?
    puts mappable_array.length
    return mappable_array#.slice(0,200)
  end

  def make_stats summary_field,fields_to_export,summary_database_path, download=false
    require 'securerandom'
    require 'time'

    summary_database = SQLite3::Database.open(summary_database_path)
    uuid = SecureRandom.uuid[0..7]
    stats_csv_filepath = "public/stats_#{Time.current.localtime.strftime("%Y-%m-%d_%H-%M-%S")}.csv"
    if download == false
      limit = "LIMIT 500"
    elsif download == true
      limit = ""
    end
    
    count_string = "SELECT #{summary_field}_summary AS 'Summarizing on #{Rails.application.config.csv_output_fields[summary_field]}', COUNT(#{summary_field}_summary) AS 'Count'"
    fields_to_export.delete('count')
    # puts fields_to_export
    fields_to_export.each {|column| count_string += ", GROUP_CONCAT(DISTINCT #{column}) AS '#{Rails.application.config.csv_output_fields[column]}'" }
    count_string += " FROM summary GROUP BY #{summary_field}_summary ORDER BY Count DESC #{limit};"
    # puts count_string
    results = summary_database.query(count_string)
    # puts results[-1].to_s
    # puts results.columns
    # results.unshift(summary_database)

    if download == false


      thead = content_tag :thead do
        content_tag :tr do
          results.columns.collect {|column| 
            concat content_tag(:th,column)
          }.join().html_safe
        end
      end

      tbody = content_tag :tbody do
        results.collect { |row|

          content_tag :tr do
            row.collect { |value|
                concat content_tag(:td, value.to_s.gsub(/([a-zA-Z0-9\.\']+?)(,)([a-zA-Z0-9]+?)/, '\1<br/>\3').html_safe, html: {class: "m-2"})
            }.to_s.html_safe
          end

        }.join().html_safe
      end

      table = content_tag(:table, class:"table table-responsive table-bordered") do 
        thead.concat(tbody)
      end

    elsif download == true
      headers = []
      fields_to_export.each do |column|
        headers << Rails.application.config.csv_output_fields[column]
      end

      headers.unshift("Count")
      headers.unshift("Summarizing on #{Rails.application.config.csv_output_fields[summary_field]}")

      CSV.open(stats_csv_filepath, "a") do |csv|
        csv << headers
        # csv << first_row
        results.each do |row|
          csv << row
        end
      end
      return stats_csv_filepath
    end

  end

  def total_stats_item_count summary_database_path
    summary_database = SQLite3::Database.open(summary_database_path)
    total_count = summary_database.query("SELECT COUNT(*) from summary").next()[0]

  end

  def create_summary_db fields_to_export,summary_field,uuid
    require 'sqlite3'
    require 'fileutils'
    db_path = "tmp/summary_#{uuid}.db"
    # puts db_path+"**\n"*50
    FileUtils.touch(db_path)
    db = SQLite3::Database.open(db_path)
    fields_columns = ""
    fields_to_export&.each do |field|
      fields_columns += ", #{field} TEXT"
    end

    sql_create_statement = "CREATE TABLE summary(#{summary_field}_summary TEXT DEFAULT '', count INTEGER DEFAULT 0#{fields_columns})"
    # puts sql_create_statement
    db.execute sql_create_statement

    return db,db_path

  end

  def get_single_solr_page requery_url_string,start_row
    require 'addressable/uri'
    requery_url_string = "#{requery_url_string}&start=#{start_row}"
    requery_url_string = Addressable::URI.parse(requery_url_string).normalize.to_s

    requery_url = URI(requery_url_string)
    # puts requery_url

    ### IGNORE SSL CERT JUST FOR TESTING
    res=nil

    Net::HTTP.start(requery_url.host, requery_url.port,
      :use_ssl => requery_url.scheme == 'https', 
      :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
      
      request = Net::HTTP::Get.new(requery_url.request_uri)
      res = http.request(request)
      # puts res
      
      
    end
  end

  # def get_single_solr_page requery_url_string,start_row
  #   requery_url_string = "#{requery_url_string}&start=#{start_row}"
  #   requery_url = URI(requery_url_string)
  #   # res = Net::HTTP.get_response(requery_url)
  #   res = nil
  #   Net::HTTP.start(requery_url.host, requery_url.port,
  #     :use_ssl => requery_url.scheme == 'https', 
  #     :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
      
  #     request = Net::HTTP::Get.new(requery_url.request_uri)
  #     res = http.request(request)
      
      
  #   end
  #   if res.is_a?(Net::HTTPSuccess) 
  #     response = JSON.parse(res.body)
  #     return response
  #   else
  #     return ""
  #   end
  # end

  def get_random_documents(query: '*', limit: 12, sort: 'random')
    params = {
      :q => query,
      :rows => limit,
      :sort => sort
    }
    builder = Blacklight::SearchService.new(config: blacklight_config, user_params: params)
    response = builder.search_results
    # puts response.inspect
    response[:response][:docs].collect { |x| x.slice(:objcsid_s,:canonicalNameComplete_s,:commonname_s,:locality_s, :blob_ss, :gardenlocation_s)}
  end

  def generate_image_gallery
    documents = get_random_documents(query: 'blob_ss:[* TO *]')
    return format_image_gallery_results(documents)
  end

  ### end search output methods ###

  def search_result_unique_label document, counter, total = nil
    label = Array(document[:objname_s] || 'untitled object').first
    if counter && counter.to_i > 0
      if total && total.to_i > 0
        label += ". #{number_with_delimiter counter} of #{number_with_delimiter total} #{'search result'.pluralize(total)}"
      else
        label += ". Search result #{number_with_delimiter counter}"
      end
    end
    label.html_safe
  end

  def render_csid csid, derivative
    "#{Rails.configuration.x.imageserver_url}/blobs/#{csid}/derivatives/#{derivative}/content"
  end

  def render_status options = {}
    options[:value].collect do |status|
      content_tag(:span, status, class: 'text-danger')
    end.join(', ').html_safe
  end

  def render_alt_text(blob_csid, options, is_external_link=false)
    document = options[:document]
    unless options[:field] == 'card_ss'
      prefix = 'Hearst Museum object'
      total_pages = document[:blob_ss] ? document[:blob_ss].length : 1
      if total_pages > 1
        page_number = document[:blob_ss].find_index(blob_csid)
        if page_number.is_a? Integer
          prefix += " #{page_number + 1} of #{total_pages}"
        end
      end
    else
      prefix = 'Documentation'
      total_pages = document[:card_ss] ? document[:card_ss].length : 1
      if total_pages > 1
        page_number = document[:card_ss].find_index(blob_csid)
        if page_number.is_a? Integer
          prefix += " page #{page_number + 1} of #{total_pages}"
        end
      end
      prefix += ' associated with Hearst Museum object'
    end
    brief_description = unless document[:objdescr_txt].nil? then "described as #{document[:objdescr_txt][0]}" else 'no description available.' end
    if document[:restrictions_ss] && document[:restrictions_ss].include?('notpublic') && !document[:restrictions_ss].include?('public')
      brief_description += ' Notice: Image restricted due to its potentially sensitive nature. Contact Museum to request access.'
    end
    object_name = unless document[:objname_txt].nil? then "titled #{document[:objname_txt][0]}" else 'no title available' end
    object_number = unless document[:objmusno_txt].nil? then "museum number #{document[:objmusno_txt][0]}" else 'no object museum number available' end
    link_description = if is_external_link then '(opens in new tab)' else '' end
    "#{prefix} #{object_name}, #{object_number}, #{brief_description} #{link_description}".html_safe
  end

  def render_media(options)
    # return a list of cards or images
    content_tag(:div) do
      options[:value].collect do |blob_csid|
        content_tag(:a,
          content_tag(:img, '',
            src: render_csid(blob_csid, 'Medium'),
            alt: render_alt_text(blob_csid, options, is_external_link=true),
            class: 'thumbclass'
          ),
          href: "#{Rails.configuration.x.imageserver_url}/blobs/#{blob_csid}/derivatives/OriginalJpeg/content",
          # href: "#{Rails.configuration.x.imageserver_url}/blobs/#{blob_csid}/content",
          target: 'original',
          style: 'padding: 4px;',
          class: 'hrefclass d-inline-block')
      end.join.html_safe
    end
  end

  # use authenticating proxy and blob csid to serve audio
  # TODO: hostname will need to change if a museum besides pahma wants to use this feature
  def render_audio_csid options = {}
    # render audio player
    content_tag(:div) do
      options[:value].collect do |audio_csid|
        source_url = "https://portal.hearstmuseum.berkeley.edu/cspace-services/blobs/#{audio_csid}/content"
        content_tag(:audio,
          content_tag(:source,
            content_tag(:p,
              [
                "I'm sorry; your browser doesn't support HTML5 audio in MPEG format. ",
                link_to('Download the MPEG', source_url, download: "#{audio_csid}.mpeg"),
                ' to play it on your device.'
              ].join.html_safe
            ),
            src: source_url,
            id: 'audio_csid',
            type: 'audio/mpeg'
          ),
          controls: 'controls'
        )
      end.join.html_safe
    end
  end

  # use authenticating proxy and blob csid to serve video
  # TODO: hostname will need to change if a museum besides pahma wants to use this feature
  def render_video_csid options = {}
    # render video player
    content_tag(:div) do
      options[:value].collect do |video_csid|
        source_url = "https://portal.hearstmuseum.berkeley.edu/cspace-services/blobs/#{video_csid}/content"
        content_tag(:video,
          content_tag(:source,
            content_tag(:p,
              [
                "I'm sorry; your browser doesn't support HTML5 video in MP4 with H.264.",
                 link_to('Download the MP4', source_url, download: "#{video_csid}.mp4"),
                ' to play it on your device.'
              ].join.html_safe
            ),
            src: source_url,
            id: 'video_csid',
            type: 'video/mp4'
          ),
          controls: 'controls'
        )
      end.join.html_safe
    end
  end

  def render_x3d_csid options = {}
    # render x3d object
    content_tag(:div) do
      options[:value].collect do |x3d_csid|
        content_tag(:x3d,
          content_tag(:scene,
            content_tag(:inline, '',
            url: "#{Rails.configuration.x.imageserver_url}/blobs/#{x3d_csid}/content",
            id: 'x3d',
            type: 'model/x3d+xml')),
          aria: {label: render_alt_text(x3d_csid, options)},
          role: 'img',
          class: 'x3d-object')
      end.join.html_safe
    end
  end

  # compute ark from museum number and render as a link
  def render_ark options = {}
    # encode museum number as ARK ID, e.g. 11-4461.1 -> hm21114461@2E1, K-3711a-f -> hm210K3711a@2Df
    options[:value].collect do |musno|
      ark = 'hm2' + if musno.include? '-'
        left, right = musno.split('-', 2)
        left = '1' + left.rjust(2, '0')
        right = right.rjust(7, '0')
        CGI.escape(left + right).gsub('%', '@').gsub('.', '@2E').gsub('-', '@2D').downcase
      else
        'x' + CGI.escape(musno).gsub('%', '@').gsub('.', '@2E').downcase
      end
      link_text = 'ark:/21549/' + ark

      link_to(
        link_text,
        'https://n2t.net/' + link_text,
        aria: {
          label: 'permalink: ' + link_text
        }
      )
    end.join.html_safe
  end
end
