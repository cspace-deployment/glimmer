# frozen_string_literal: true

class ThumbnailPresenter < Blacklight::ThumbnailPresenter

  def render_thumbnail_alt_text()
    prefix = document[:itemclass_s] || 'BAMPFA object'
    title = unless document[:title_s].nil? then "titled #{document[:title_s]}" else 'no title available' end
    materials = document[:materials_s] || 'of unknown materials'
    object_number = unless document[:idnumber_s].nil? then "accession number #{document[:idnumber_s]}" else 'no accession number available' end
    "#{prefix} #{title}, #{materials}, #{object_number}".html_safe
  end

  private

  # @param [Hash] image_options to pass to the image tag
  def thumbnail_value(image_options)
    value = if thumbnail_method
              view_context.send(thumbnail_method, document, image_options)
            elsif thumbnail_field
              image_options['alt'] = render_thumbnail_alt_text
              image_url = "#{Rails.configuration.x.imageserver_url}/blobs/" + thumbnail_value_from_document + '/derivatives/Medium/content'
              # image_options[:width] = '200px'
              view_context.image_tag image_url, image_options if image_url.present?
            end

    value || default_thumbnail_value(image_options)
  end

end
