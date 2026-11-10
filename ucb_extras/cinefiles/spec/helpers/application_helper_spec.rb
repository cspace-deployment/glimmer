# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  include Devise::Test::ControllerHelpers

  before(:all) do
    @config = Blacklight::Configuration.new do |config|
      config.index.title_field = 'common_title_ss'
    end
  end

  before do
    allow(helper).to receive(:blacklight_config).and_return(@config)
  end

  describe '#search_result_unique_label' do
    subject { helper.search_result_unique_label(document, counter, total) }

    let(:document) { SolrDocument.new(common_doctype_s: 'film', common_title_ss: ['Felix the Cat', 'Felix Goes West']) }
    let(:counter) { 5 }
    let(:total) { 2000 }

    it 'provides a unique accessible label for a document in the search results' do
      expect(subject).to eq "Felix the Cat, Felix Goes West. 5 of 2,000 search results"
      expect(subject).to be_html_safe
    end

    context "when there is only one search result" do
      let(:counter) { 1 }
      let(:total) { 1 }

      it 'does not pluralize' do
        expect(subject).to eq "Felix the Cat, Felix Goes West. 1 of 1 search result"
        expect(subject).to be_html_safe
      end
    end

    context "when counter is nil (i.e. in the 'show' view)" do
      let(:counter) { nil }
      it 'does not include counter or total' do
        expect(subject).to eq "Felix the Cat, Felix Goes West"
        expect(subject).to be_html_safe
      end
    end

    context "when counter is provided but total is nil" do
      let(:total) { nil }
      it 'does not include total' do
        expect(subject).to eq "Felix the Cat, Felix Goes West. Search result 5"
        expect(subject).to be_html_safe
      end
    end
  end

  describe '#render_csid' do
    let(:csid) { 123 }
    let(:derivative) { 'medium' }

    it 'returns an image URL for the given csid and derivative' do
      expect(helper.render_csid(csid, derivative)).to eq "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{csid}/derivatives/#{derivative}/content"
    end
  end

  describe '#render_multiline' do
    subject { helper.render_multiline(options) }

    let(:options) { {value: ['life', 'death', 123]} }

    it 'renders an array of values as a list' do
      expect(subject).to have_selector 'div > ul > li:nth-child(1)', text: 'life'
      expect(subject).to have_selector 'div > ul > li:nth-child(2)', text: 'death'
      expect(subject).to have_selector 'div > ul > li:nth-child(3)', text: '123'
      expect(subject).to be_html_safe
    end
  end

  describe '#render_film_links' do
    subject { helper.render_film_links(options) }

    let(:options) { {
      value: [
        'pfafilm1++Der knabe im blau (The child in blue)++ — Murnau, F. W. — Germany — 1919',
        'pfafilm2++Schloss vogelöd (Castle vogelöd)++ — Murnau, F. W. — Germany — 1921',
        'pfafilm3++Nosferatu - eine symphonie des grauens (Nosferatu the vampire)++ — Murnau, F. W. — Germany — 1922',
        'pfafilm4++Tartüff++ — Murnau, F. W. — Germany — 1926'
      ]
    } }

    it 'renders an array of films as a list of links' do
      expect(subject).to have_selector 'div > ul > li:nth-child(1)' do |s|
        expect(s).to have_text 'Der knabe im blau (The child in blue) — Murnau, F. W. — Germany — 1919'
        expect(s).to have_link 'Der knabe im blau (The child in blue)', href: '/catalog/pfafilm1'
      end
      expect(subject).to have_selector 'div > ul > li:nth-child(2)' do |s|
        expect(s).to have_text 'Schloss vogelöd (Castle vogelöd) — Murnau, F. W. — Germany — 1921'
        expect(s).to have_link 'Schloss vogelöd (Castle vogelöd)', href: '/catalog/pfafilm2'
      end
      expect(subject).to have_selector 'div > ul > li:nth-child(3)' do |s|
        expect(s).to have_text 'Nosferatu - eine symphonie des grauens (Nosferatu the vampire) — Murnau, F. W. — Germany — 1922'
        expect(s).to have_link 'Nosferatu - eine symphonie des grauens (Nosferatu the vampire)', href: '/catalog/pfafilm3'
      end
      expect(subject).to have_selector 'div > ul > li:nth-child(4)' do |s|
        expect(s).to have_text 'Tartüff — Murnau, F. W. — Germany — 1926'
        expect(s).to have_link 'Tartüff', href: '/catalog/pfafilm4'
      end
      expect(subject).to be_html_safe
    end
  end

  describe '#render_doc_link' do
    subject { helper.render_doc_link(options) }

    let(:film_id) { 'pfafilm4' }
    let(:film_title) { 'Tartüff' }
    let(:film_year) { '1926' }
    let(:options) { {
      document: SolrDocument.new({film_title_ss: [film_title], film_year_ss: [film_year]}),
      value: [film_id]
    } }
    it 'renders a link to a search for documents related to a film' do
      expect(subject).to have_link 'Documents related to this film' do |link|
        expect(link['href']).to eq "/?q=#{film_id}&search_field=film_id_ss"
        expect(link['aria-label']).to eq "Documents related to the film \"#{film_title}\", #{film_year}"
      end
      expect(subject).to be_html_safe
    end
  end

  describe '#render_warc' do
    subject { helper.render_warc(options) }

    let(:warc_url) { 'https://cinefiles-web-archives.s3.us-west-1.amazonaws.com/abc-film-festival-2022-03-08.wacz' }
    let(:canonical_url) { 'https://www.abcfilmfest.org/' }
    let(:options) { {
      document: SolrDocument.new({doctype_s: 'web archive', docurl_s: warc_url, canonical_url_s: canonical_url})
    } }

    it 'renders a web archive' do
      expect(subject).to have_selector ".warc-container > .warc > replay-web-page[source=\"#{warc_url}\"][url=\"#{canonical_url}\"]"
      expect(subject).to be_html_safe
    end
  end

  describe '#check_and_render_pdf' do
    subject { helper.check_and_render_pdf(options) }

    before do
      allow(helper).to receive(:current_user).and_return nil
    end

    let(:film_id) { 'pfafilm1' }
    let(:options) { {
      document: SolrDocument.new({code_s: access_code}),
      value: [film_id]
    } }

    shared_examples 'the PDF is not restricted' do
      it 'renders a PDF and a link to open it' do
        expect(subject).to have_selector '#pdf' do |s|
          expect(s).to have_link 'view full size in new window', href: "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{film_id}/content/linked_pdf:#{helper.current_user}"
          expect(s).to have_selector "object[data=\"https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{film_id}/content/inline_pdf:#{helper.current_user}\"]"
          expect(subject).to be_html_safe
        end
      end
    end

    context 'when access code is 4' do
      let(:access_code) { '4' }
      it_behaves_like 'the PDF is not restricted'
    end

    context 'when access code is not 4' do
      let(:access_code) { '3' }

      it 'renders a PDF restriction notice' do
        expect(subject).to have_selector '#copyrightstatement > h2', text: 'A PDF of this document is available'
        expect(subject).to have_selector '#copyrightstatement > .panel-title', text: 'Materials from the BAMPFA Film Library and Study Center’s CineFiles project
      may be protected by U.S. copyright, and possibly other statutes, even if no copyright symbol appears. Please be advised that we are providing these materials for personal study purposes only, following sections 107 (Fair Use) and 108 (Reproduction by Libraries and Archives) of the U.S. Copyright Act; please contact the publisher to obtain permission for any other type of use.'
        expect(subject).to have_selector '#copyrightstatement a[type="button"]', text: 'Sign me up!'
        expect(subject).to have_selector '#copyrightstatement a[type="button"]', text: 'Log in'
        expect(subject).to be_html_safe
      end

      context 'but user is authenticated' do
        before do
          allow(helper).to receive(:current_user).and_return 'test@berkeley.edu'
        end

        it_behaves_like 'the PDF is not restricted'
      end
    end
  end

  describe '#render_alt_text' do
    subject { helper.render_alt_text(blob_csid, options) }

    context 'when object has no data' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({}) }
      let(:options) { {document: document} }

      it 'provides minimal alt text' do
        expect(subject).to eq 'Document no title available'
      end
    end

    context 'when object has more than one image' do
      let(:blob_csid) { 2 }
      let(:document) { SolrDocument.new({blob_ss: [1, 2, 3], common_doctype_s: 'document'}) }
      let(:options) { {document: document} }

      it 'includes image number and total images in the alt text' do
        expect(subject).to eq 'Document page 2 of 3 no title available'
      end
    end

    context 'when object has a type' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({doctype_s: 'Film'}) }
      let(:options) { {document: document} }

      it 'includes the type in the alt text' do
        expect(subject).to eq 'Film no title available'
      end
    end

    context 'when object has a title' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({doctitle_ss: ["Kutsal Damacana 2: İtmen"]}) }
      let(:options) { {document: document} }

      it 'includes the title in the alt text' do
        expect(subject).to eq "Document titled Kutsal Damacana 2: İtmen"
      end
    end

    context 'when object has a source' do
      let(:blob_csid) { nil }
      let(:document) { SolrDocument.new({source_s: 'Sözcü'}) }
      let(:options) { {document: document} }

      it 'includes the title in the alt text' do
        expect(subject).to eq "Document no title available, source: Sözcü"
      end
    end

    context 'when object has a type, title, source, and more than one image' do
      let(:blob_csid) { 2 }
      let(:document) do
        SolrDocument.new({
          blob_ss: [1, 2, 3],
          doctype_s: 'Film',
          doctitle_ss: ["Kutsal Damacana 2: İtmen"],
          source_s: 'Sözcü'
        })
      end
      let(:options) { {document: document} }

      it 'includes them in the alt text' do
        expect(subject).to eq "Film 2 of 3 titled Kutsal Damacana 2: İtmen, source: Sözcü"
      end
    end
  end

  describe '#render_media' do
    subject { helper.render_media(options) }

    let(:blob_csid) { '123abc' }
    let(:document) { SolrDocument.new({}) }
    let(:options) { {document: document, value: [blob_csid]} }
    let(:expected_href) { "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{blob_csid}/derivatives/OriginalJpeg/content" }
    let(:expected_img_src) { "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{blob_csid}/derivatives/Medium/content" }

    it 'wraps each image in a link to that image' do
      expect(subject).to have_link(href: expected_href)
      expect(subject).to have_selector 'a.d-inline-block > img.thumbclass'
      expect(subject).to be_html_safe
    end

    it "renders each image with alt text " do
      expect(subject).to have_selector("img[src=\"#{expected_img_src}\"]")
      expect(subject).to have_selector("img[alt=\"Document no title available\"]")
    end
  end

  describe '#render_linkless_media' do
    subject { helper.render_linkless_media(options) }

    let(:blob_csid) { '123abc' }
    let(:document) { SolrDocument.new({}) }
    let(:options) { {document: document, value: [blob_csid]} }
    let(:expected_img_src) { "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{blob_csid}/derivatives/Medium/content" }

    it 'does not wrap each image in a link' do
      expect(subject).not_to have_link
      expect(subject).to have_selector 'div.d-inline-block > img.thumbclass'
      expect(subject).to be_html_safe
    end

    it "renders each image with alt text" do
      expect(subject).to have_selector "img[src=\"#{expected_img_src}\"]"
      expect(subject).to have_selector("img[alt=\"Document no title available\"]")
    end
  end

  describe '#render_restricted_media' do
    subject { helper.render_restricted_media(options) }

    let(:blob_csid) { '123abc' }
    let(:document) { SolrDocument.new({}) }
    let(:options) { {document: document, value: [blob_csid]} }
    let(:expected_img_src) { "https://webapps.cspace.berkeley.edu/cinefiles/imageserver/blobs/#{blob_csid}/derivatives/Medium/content" }

    context 'when user is anonymous' do
      it 'renders a placeholder with alt text for each image' do
        expect(subject).not_to have_link
        expect(subject).to have_selector 'div > img.thumbclass'
        expect(subject).to have_selector 'img[src="../kuchar.jpg"]'
        expect(subject).to have_selector 'img[alt="log in to view images"]'
        expect(subject).to be_html_safe
      end
    end

    context 'when user is authenticated' do
      before do
        allow(helper).to receive(:current_user).and_return true
      end

      it 'renders each image with alt text' do
        expect(subject).not_to have_link
        expect(subject).to have_selector 'div > img.thumbclass'
        expect(subject).to have_selector "img[src=\"#{expected_img_src}\"]"
        expect(subject).to have_selector("img[alt=\"Document no title available\"]")
        expect(subject).to be_html_safe
      end
    end
  end
  context 'when IMAGESERVER_URL is set' do
    around do |example|
      default_url = Rails.configuration.x.imageserver_url
      Rails.configuration.x.imageserver_url = 'https://images.example.org/cinefiles/imageserver'
      example.run
    ensure
      Rails.configuration.x.imageserver_url = default_url
    end

    let(:csid) { '123abc' }
    let(:options) { { document: SolrDocument.new({}), value: [ csid ] } }

    it 'uses it for images and the original JPEG' do
      expect(helper.render_csid(csid, 'Medium')).to eq "https://images.example.org/cinefiles/imageserver/blobs/#{csid}/derivatives/Medium/content"
      expect(helper.render_media(options)).to have_link(href: "https://images.example.org/cinefiles/imageserver/blobs/#{csid}/derivatives/OriginalJpeg/content")
    end
  end
end
