# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  include Devise::Test::ControllerHelpers

  before(:all) do
    @config = Blacklight::Configuration.new do |config|
      config.index.title_field = 'title_s'
    end
  end

  before do
    allow(helper).to receive(:blacklight_config).and_return(@config)
  end

  let(:mock_response) { instance_double(Blacklight::Solr::Response) }
  let(:mock_document) { instance_double(SolrDocument, export_formats: {}) }
  let(:search_service) { instance_double(Blacklight::SearchService) }

  describe '#search_result_unique_label' do
    subject { helper.search_result_unique_label(document, counter, total) }

    let(:document) { SolrDocument.new(title_s: 'Felix the Cat', idnumber_s: '123-abc') }
    let(:counter) { 5 }
    let(:total) { 2000 }

    it 'provides a unique accessible label for a document in the search results' do
      expect(subject).to eq "Felix the Cat. 5 of 2,000 search results"
      expect(subject).to be_html_safe
    end

    context "when there is only one search result" do
      let(:counter) { 1 }
      let(:total) { 1 }

      it 'does not pluralize' do
        expect(subject).to eq "Felix the Cat. 1 of 1 search result"
        expect(subject).to be_html_safe
      end
    end

    context "when counter is nil (i.e. in the 'show' view)" do
      let(:counter) { nil }
      it 'does not include counter or total' do
        expect(subject).to eq "Felix the Cat"
        expect(subject).to be_html_safe
      end
    end

    context "when counter is provided but total is nil" do
      let(:total) { nil }
      it 'does not include total' do
        expect(subject).to eq "Felix the Cat. Search result 5"
        expect(subject).to be_html_safe
      end
    end
  end

  describe '#generate_image_gallery' do
    subject { helper.generate_image_gallery() }

    before do
      allow_any_instance_of(Blacklight::SearchService).to receive(:search_results).and_return(mock_response)
    end

    let(:mock_response) do
      {
        response: {
          docs: documents
        }
      }
    end
    let(:documents) do
      ids = (1..12).to_a
      ids.map do |id|
        {
          :id => id,
          :title_txt => ["title #{id}"],
          :artistcalc_txt => ["artist #{id}"],
          :datemade_s => "date made #{id}",
          :blob_ss => ["blob-#{id}"],
          :materials_s => "materials #{id}",
          :idnumber_s => "accession number #{id}",
          :itemclass_s => "classification #{id}"
        }
      end
    end

    it 'renders a list of randomly selected documents' do
      documents.each_with_index do |doc, index|
        expected_img_src = "https://webapps.cspace.berkeley.edu/bampfa/imageserver/blobs/#{doc[:blob_ss][0]}/derivatives/Medium/content"
        expected_img_alt = "#{doc[:itemclass_s]} titled #{doc[:title_txt][0]}, #{doc[:materials_s]}, accession number #{doc[:idnumber_s]}."
        expect(subject).to have_link href: "/catalog/#{doc[:id]}" do |link|
          expect(link).to have_selector "img[src=\"#{expected_img_src}\"][alt=\"#{expected_img_alt}\"]"
        end

        item_selector = "div.gallery-item:nth-child(#{index + 1})"
        expect(subject).to have_selector "#{item_selector} .gallery-caption-title", text: doc[:title_txt][0]
        expect(subject).to have_selector "#{item_selector} .gallery-caption-date", text: "(#{doc[:datemade_s]})"
        expect(subject).to have_selector "#{item_selector} .gallery-caption-artist", text: "by #{doc[:artistcalc_txt][0]}"
        expect(subject).to have_link doc[:artistcalc_txt][0], href: "/catalog/?&op=OR&search_field=artistcalc_s&q=\"#{doc[:artistcalc_txt][0].sub(' ', '+')}\""
        expect(subject).to be_html_safe
      end
    end
  end

  describe '#extract_artist_names' do
    pending 'TODO: test with different inputs, multiple artists, etc'
  end

  describe '#format_image_gallery_results' do
    pending 'TODO: test on documents with missing data'
  end

  describe '#render_csid' do
    let(:csid) { 123 }
    let(:derivative) { 'medium' }

    it 'returns an image URL for the given csid and derivative' do
      expect(helper.render_csid(csid, derivative)).to eq "https://webapps.cspace.berkeley.edu/bampfa/imageserver/blobs/#{csid}/derivatives/#{derivative}/content"
    end
  end

  describe '#render_alt_text' do
    subject { helper.render_alt_text(blob_csid, document) }

    context 'when object has no data' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({}) }

      it 'provides minimal alt text' do
        expect(subject).to eq 'BAMPFA object no title available, of unknown materials, no accession number available.'
      end
    end

    context 'when object has more than one image' do
      let(:blob_csid) { 2 }
      let(:document) { SolrDocument.new({blob_ss: [1, 2, 3]}) }

      it 'includes image number and total images in the alt text' do
        expect(subject).to eq 'BAMPFA object 2 of 3 no title available, of unknown materials, no accession number available.'
      end
    end

    context 'when object has a classification' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({itemclass_s: 'Ephemera'}) }

      it 'includes the type in the alt text' do
        expect(subject).to eq 'Ephemera no title available, of unknown materials, no accession number available.'
      end
    end

    context 'when object has a title' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({title_txt: ["Kutsal Damacana 2: İtmen"]}) }

      it 'includes the title in the alt text' do
        expect(subject).to eq "BAMPFA object titled Kutsal Damacana 2: İtmen, of unknown materials, no accession number available."
      end
    end

    context 'when object has materials' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({materials_s: 'photogravure'}) }

      it 'includes the title in the alt text' do
        expect(subject).to eq "BAMPFA object no title available, photogravure, no accession number available."
      end
    end

    context 'when object has an accession number' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({idnumber_s: '123-abc'}) }

      it 'includes the title in the alt text' do
        expect(subject).to eq "BAMPFA object no title available, of unknown materials, accession number 123-abc."
      end
    end

    context 'when object has a classification, title, materials, accession number, and more than one image' do
      let(:blob_csid) { 2 }
      let(:document) do
        SolrDocument.new({
          blob_ss: [1, 2, 3],
          itemclass_s: 'Ephemera',
          title_txt: ["Kutsal Damacana 2: İtmen"],
          materials_s: 'photogravure',
          idnumber_s: '123-abc'
        })
      end

      it 'includes them in the alt text' do
        expect(subject).to eq "Ephemera 2 of 3 titled Kutsal Damacana 2: İtmen, photogravure, accession number 123-abc."
      end
    end
  end

  describe '#render_media' do
    subject { helper.render_media(options) }

    let(:blob_csid) { '123abc' }
    let(:document) { SolrDocument.new({}) }
    let(:options) { {document: document, value: [blob_csid]} }
    let(:expected_href) { "https://webapps.cspace.berkeley.edu/bampfa/imageserver/blobs/#{blob_csid}/derivatives/OriginalJpeg/content" }
    let(:expected_img_src) { "https://webapps.cspace.berkeley.edu/bampfa/imageserver/blobs/#{blob_csid}/derivatives/Medium/content" }

    it 'wraps each image in a link to that image' do
      expect(subject).to have_link(href: expected_href)
      expect(subject).to have_selector 'a.d-inline-block > img.thumbclass'
      expect(subject).to be_html_safe
    end

    it "renders each image with alt text " do
      expect(subject).to have_selector("img[src=\"#{expected_img_src}\"]")
      expect(subject).to have_selector("img[alt=\"BAMPFA object no title available, of unknown materials, no accession number available.\"]")
    end
  end
  context 'when IMAGESERVER_URL is set' do
    around do |example|
      default_url = Rails.configuration.x.imageserver_url
      Rails.configuration.x.imageserver_url = 'https://images.example.org/bampfa/imageserver'
      example.run
    ensure
      Rails.configuration.x.imageserver_url = default_url
    end

    let(:csid) { '123abc' }
    let(:options) { { document: SolrDocument.new({}), value: [ csid ] } }

    it 'uses it for images and the original JPEG' do
      expect(helper.render_csid(csid, 'Medium')).to eq "https://images.example.org/bampfa/imageserver/blobs/#{csid}/derivatives/Medium/content"
      expect(helper.render_media(options)).to have_link(href: "https://images.example.org/bampfa/imageserver/blobs/#{csid}/derivatives/OriginalJpeg/content")
    end
  end
end
