# frozen_string_literal: true
require 'cgi/util'

module ApplicationHelper
  include ERB::Util

  def search_result_unique_label document, counter, total = nil
    label = Array(document['title_s'] || 'untitled object').first
    if counter && counter.to_i > 0
      if total && total.to_i > 0
        label += ". #{number_with_delimiter counter} of #{number_with_delimiter total} #{'search result'.pluralize(total)}"
      else
        label += ". Search result #{number_with_delimiter counter}"
      end
    end
    label.html_safe
  end

  def get_random_documents(query: '*', limit: 12)
    params = {
      :q => query,
      :rows => limit,
      :sort => 'random'
    }
    builder = Blacklight::SearchService.new(config: blacklight_config, user_params: params)
    response = builder.search_results
    docs = response[:response][:docs].collect { |x| x.slice(:id, :title_txt, :artistcalc_txt, :datemade_s, :blob_ss, :materials_s, :idnumber_s, :itemclass_s)}
    return docs
  end

  def generate_image_gallery
    docs = get_random_documents(query: 'blob_ss:[* TO *]')
    return format_image_gallery_results(docs)
  end

  def generate_artist_preview(artist)#,limit=4)
    # artist should already include parsed artist names
    # this should return format_artist_preview()
    searchable = extract_artist_names(html_escape(artist))
    searchable = searchable.split(" OR ")
    random_string = SecureRandom.uuid
    query = ""
    searchable.each do |x|
      query = query + "#{x}"
    end

    docs = get_random_documents(query: query, limit: 4)
    if docs.blank?
      return content_tag(:div, 'No related works found.').html_safe
    else
      return docs.collect do |doc|
        content_tag(:a, href: "/catalog/#{doc[:id]}") do
          content_tag(:div, class: 'show-preview-item') do
            unless doc[:title_txt].nil?
              title = doc[:title_txt][0]
            else
              title = "[No title given]"
            end
            unless doc[:artistcalc_txt].nil?
              artist = doc[:artistcalc_txt][0]
            else
              artist = "[No artist given]"
            end
            artist_tag = content_tag(:span, artist, class: "gallery-caption-artist")
            unless doc[:datemade_s].nil?
              datemade = doc[:datemade_s]
            else
              datemade = "[No date given]"
            end
            unless doc[:blob_ss].nil?
              image_tag = content_tag(:img, '',
                src: render_csid(doc[:blob_ss][0], 'Medium'),
                alt: render_alt_text(doc[:blob_ss][0], doc),
                class: 'thumbclass')
            else
              image_tag = content_tag(:span,'Image not available',class: 'no-preview-image')
            end
            image_tag +
            content_tag(:div) do
              artist_tag +
              content_tag(:span, title, class: "gallery-caption-title") +
              content_tag(:span, "("+datemade+")", class: "gallery-caption-date")
            end
          end
        end
      end.join.html_safe
    end
  end

  def extract_artist_names(artist_html)
    artist = CGI.unescapeHTML(artist_html)
    searchable = artist.tr(",","") # first remove commas
    matches = searchable.scan(/[^;]+(?=;?)/) # find the names in between optional semi-colons
    if matches.length != 0
      matches = matches.each{|m| m.lstrip!}
      matches.map!{|m| m.tr(" ","+").insert(0,'"').insert(-1,'"')} # add quotes for the OR search
      searchable = matches.join(" OR ")
    end
    return searchable
  end

  def make_artist_search_link(artist)
    searchable = extract_artist_names(artist)
    return "/catalog/?&op=OR&search_field=artistcalc_s&q=#{searchable}"
  end

  def format_image_gallery_results(docs)
    docs.collect do |doc|
      content_tag(:div, class: 'gallery-item') do
        unless doc[:title_txt].nil?
          title = doc[:title_txt][0]
        else
          title = "[No title given]"
        end
        unless doc[:artistcalc_txt].nil?
          artist = doc[:artistcalc_txt][0]
          artist_link = make_artist_search_link(artist)
          artist_tag = content_tag(:span, class: "gallery-caption-artist") do
            "by ".html_safe +
            content_tag(:a, artist, href: artist_link)
          end
        else
          artist_tag = content_tag(:span, "[No artist given]", class: "gallery-caption-artist")
        end
        unless doc[:datemade_s].nil?
          datemade = doc[:datemade_s]
        else
          datemade = "[No date given]"
        end
        content_tag(:a,
          content_tag(:img, '',
            src: render_csid(doc[:blob_ss][0], 'Medium'),
            alt: render_alt_text(doc[:blob_ss][0], doc),
            class: 'thumbclass'
          ),
          href: "/catalog/#{doc[:id]}",
          class: 'd-inline-block'
        ) +
        content_tag(:div, class: 'mt-1') do
          content_tag(:span, title, class: "gallery-caption-title") +
          content_tag(:span, "("+datemade+")", class: "gallery-caption-date") +
          artist_tag
        end
      end
    end.join.html_safe
  end

  def render_csid csid, derivative
    "#{Rails.configuration.x.imageserver_url}/blobs/#{csid}/derivatives/#{derivative}/content"
  end

  def render_alt_text blob_csid, document
    prefix = document[:itemclass_s] || 'BAMPFA object'
    total_pages = document[:blob_ss] ? document[:blob_ss].length : 1
    if total_pages > 1
      page_number = document[:blob_ss].find_index(blob_csid)
      if page_number.is_a? Integer
        prefix += " #{page_number + 1} of #{total_pages}"
      end
    end
    title = unless document[:title_txt].nil? then "titled #{document[:title_txt][0]}" else 'no title available' end
    materials = document[:materials_s] || 'of unknown materials'
    object_number = unless document[:idnumber_s].nil? then "accession number #{document[:idnumber_s]}" else 'no accession number available' end
    html_escape("#{prefix} #{title}, #{materials}, #{object_number}.")
  end

  def render_media options = {}
    # return a list of cards or images
    content_tag(:div) do
      options[:value].collect do |blob_csid|
        content_tag(:a,
          content_tag(:img, '',
            src: render_csid(blob_csid, 'Medium'),
            alt: render_alt_text(blob_csid, options),
            class: 'thumbclass'
          ),
          href: "#{Rails.configuration.x.imageserver_url}/blobs/#{blob_csid}/derivatives/OriginalJpeg/content",
          # href: "#{Rails.configuration.x.imageserver_url}/blobs/#{blob_csid}/content",
          target: 'original',
          style: 'padding: 3px;',
          class: 'hrefclass d-inline-block')
      end.join.html_safe
    end
  end
end
