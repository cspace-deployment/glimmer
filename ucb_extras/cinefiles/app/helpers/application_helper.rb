
# frozen_string_literal: true

module ApplicationHelper

  def search_result_unique_label document, counter, total = nil
    label = if document['common_title_ss'] then document['common_title_ss'].join(', ') else "Untitled #{document[:doctype_s] || 'Document'}" end
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

  def render_multiline options = {}
    # render an array of values as a list
    content_tag(:div) do
      content_tag(:ul) do
        options[:value].collect do |array_element|
          content_tag(:li, array_element)
        end.join.html_safe
      end
    end
  end

  def render_film_links options = {}
    # return a <ul> of films with links to the films themselves
    content_tag(:div) do
      content_tag(:ul) do
        options[:value].collect do |array_element|
          parts = array_element.split(/^(.*?)\+\+(.*?)\+\+(.*)/)
          content_tag(:li, (link_to parts[2], '/catalog/' + parts[1]) + parts[3]) unless parts.length < 4
        end.join.html_safe
      end
    end
  end

  def render_doc_link options = {}
    # return a link to a search for documents for a film
    content_tag(:div) do
      film_title = options[:document][:film_title_ss].first
      film_year = if options[:document][:film_year_ss] then options[:document][:film_year_ss].first else '' end
      options[:value].collect do |film_id|
        content_tag(:a, 'Documents related to this film',
          href: "/?q=#{film_id}&search_field=film_id_ss",
          style: 'padding: 3px;',
          class: 'hrefclass',
          'aria-label': "Documents related to the film \"#{film_title}\", #{film_year}")
      end.join.html_safe
    end
  end

  def render_warc options = {}
    doc_type = options[:document][:doctype_s]
    warc_url = options[:document][:docurl_s]
    canonical_url = options[:document][:canonical_url_s]
    unless warc_url.nil?
      if doc_type == 'web archive'
        render partial: '/shared/warcs', locals: { warc_url: warc_url, canonical_url: canonical_url }
      end
    end
  end

  def check_and_render_pdf options = {}
    # access_code is set by by complicated SQL expression and results in an integer code_s in solr
    access_code = options[:document][:code_s]
    # access_code==4 => "World", everything else is restricted
    if access_code == '4'
      restricted = false
    else
      restricted = true
    end
    render_pdf options[:value].first, restricted
  end

  def render_pdf pdf_csid, restricted
    # render a pdf using html5 pdf viewer
    render partial: '/shared/pdfs', locals: { csid: pdf_csid, restricted: restricted }
  end

  def render_alt_text(blob_csid, options)
    document = options[:document]
    prefix = document[:doctype_s] || 'Document'
    total_pages = document[:blob_ss] ? document[:blob_ss].length : 1
    if total_pages > 1
      page_number = document[:blob_ss].find_index(blob_csid)
      if page_number.is_a? Integer
        if document[:common_doctype_s] == 'document'
          prefix += ' page'
        end
        prefix += " #{page_number + 1} of #{total_pages}"
      end
    end
    document_title = unless document[:doctitle_ss].nil? then "titled #{document[:doctitle_ss][0]}" else 'no title available' end
    source = unless document[:source_s].nil? then ", source: #{document[:source_s]}" else '' end
    h("#{prefix} #{document_title}#{source}")
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
          class: 'hrefclass d-inline-block'
        )
      end.join.html_safe
    end
  end

  def render_linkless_media options = {}
    # return a list of cards or images
    content_tag(:div) do
      options[:value].collect do |blob_csid|
        content_tag(:div,
          content_tag(:img, '',
            src: render_csid(blob_csid, 'Medium'),
            alt: render_alt_text(blob_csid, options),
            class: 'thumbclass'
          ),
          class: 'd-inline-block',
          style: 'padding: 3px;')
      end.join.html_safe
    end
  end

  def render_restricted_media options = {}
    # return a list of cards or images
    content_tag(:div) do
      if current_user
        options[:value].collect do |blob_csid|
          content_tag(:img, '',
              src: render_csid(blob_csid, 'Medium'),
              alt: render_alt_text(blob_csid, options),
              class: 'thumbclass')
        end.join.html_safe
      else content_tag(:img, '',
              src: '../kuchar.jpg',
              class: 'thumbclass',
              alt: 'log in to view images')
      end
    end
  end
end
