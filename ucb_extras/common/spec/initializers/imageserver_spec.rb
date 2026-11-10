# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imageserver do
  describe '.url_from' do
    let(:default_url) { 'https://webapps.cspace.berkeley.edu/#TENANT#/imageserver' }

    it 'uses the production imageserver when the value is unset' do
      expect(described_class.url_from(nil)).to eq default_url
    end

    it 'treats an empty or blank value as unset' do
      expect(described_class.url_from('')).to eq default_url
      expect(described_class.url_from('  ')).to eq default_url
    end

    it 'uses the given value' do
      expect(described_class.url_from('https://images.example.org/#TENANT#/imageserver')).to eq 'https://images.example.org/#TENANT#/imageserver'
    end

    it 'strips trailing slashes and surrounding spaces' do
      expect(described_class.url_from(' https://images.example.org/#TENANT#/imageserver// ')).to eq 'https://images.example.org/#TENANT#/imageserver'
    end
  end

  it 'sets config.x.imageserver_url from IMAGESERVER_URL' do
    expect(Rails.configuration.x.imageserver_url).to eq described_class.url_from(ENV['IMAGESERVER_URL'])
  end
end
