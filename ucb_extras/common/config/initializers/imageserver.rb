# Be sure to restart your server when you modify this file.

# Base URL of the server that serves blobs (images, derivatives, PDFs, 3D files):
# links are built as "#{imageserver_url}/blobs/<csid>/...".
# Set the IMAGESERVER_URL environment variable (e.g. with SetEnv in the Apache vhost)
# to use another server; an empty value means unset, and a trailing slash is ignored.
module Imageserver
  DEFAULT_URL = "https://webapps.cspace.berkeley.edu/#TENANT#/imageserver"

  def self.url_from(value)
    url = value.to_s.strip.sub(%r{/+\z}, "")
    url.empty? ? DEFAULT_URL : url
  end
end

Rails.application.config.x.imageserver_url = Imageserver.url_from(ENV["IMAGESERVER_URL"])
