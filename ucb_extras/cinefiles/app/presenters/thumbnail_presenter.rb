# frozen_string_literal: true

class ThumbnailPresenter < Blacklight::ThumbnailPresenter

  def render_thumbnail_alt_text()
    prefix = document[:doctype_s] || 'Document'
    total_pages = document[:blob_ss] ? document[:blob_ss].length : 1
    if total_pages > 1
      page_number = "#{document[:blob_ss].find_index(thumbnail_value_from_document)}".to_i
      if page_number.to_s.instance_of?(String)
        if document[:common_doctype_s] == 'document'
          prefix += ' page '
        end
        prefix += "#{page_number + 1} of #{total_pages}"
      end
    end
    document_title = unless document[:doctitle_ss].nil? then " titled #{document[:doctitle_ss][0]}" else ', no title available' end
    source = unless document[:source_s].nil? then ", source: #{document[:source_s]}" else '' end
    "#{prefix}#{document_title}#{source}".html_safe
  end

  private

  # @param [Hash] image_options to pass to the image tag
  def thumbnail_value(image_options)
    value = if thumbnail_method
              view_context.send(thumbnail_method, document, image_options)
            elsif thumbnail_field
              image_options['alt'] = render_thumbnail_alt_text
              image_url = "#{Rails.configuration.x.imageserver_url}/blobs/" + thumbnail_value_from_document + '/derivatives/Medium/content'
              view_context.image_tag image_url, image_options if image_url.present?
            end

    value || default_thumbnail_value(image_options)
  end

end
