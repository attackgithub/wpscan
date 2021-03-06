# frozen_string_literal: true

shared_examples 'WordPress::CustomDirectories' do
  let(:fixtures) { super().join('custom_directories') }

  describe '#content_dir' do
    {
      default: 'wp-content', https: 'wp-content', custom_w_spaces: 'custom content spaces',
      relative_one: 'wp-content', relative_two: 'wp-content', cache: 'wp-content',
      in_raw_js: 'wp-content', with_sub_dir: 'app', relative_two_sub_dir: 'cms/wp-content'
    }.each do |file, expected|
      it "returns #{expected} for #{file}.html" do
        stub_request(:get, target.url).to_return(body: File.read(fixtures.join("#{file}.html")))

        expect(target.content_dir).to eql expected
      end
    end

    context 'when not found via the homepage' do
      before { stub_request(:get, target.url).to_return(body: '') }

      context 'when detection mode is passive' do
        it 'returns nil' do
          expect(target).not_to receive(:default_content_dir_exist?)

          expect(target.content_dir(:passive)).to eql nil
        end
      end

      context 'when detection mode is mixed or aggressive' do
        before { expect(target).to receive(:default_content_dir_exists?).and_return(dir_exist) }

        %i[mixed aggressive].each do |mode|
          context 'when default content dir exists' do
            let(:dir_exist) { true }

            it 'returns wp-content' do
              expect(target.content_dir(mode)).to eql 'wp-content'
            end
          end

          context 'when default content dir does not exist' do
            let(:dir_exist) { false }

            it 'returns nil' do
              expect(target.content_dir(mode)).to eql nil
            end
          end
        end
      end
    end
  end

  describe 'default_content_dir_exists?' do
    before do
      expect(target).to receive(:head_or_get_params).and_return(method: :head)
      stub_request(:head, target.uri.join('wp-content/').to_s).to_return(status: status)
    end

    context 'when 404' do
      let(:status) { 404 }

      its(:default_content_dir_exists?) { should be false }
    end

    context 'when 200, 401 or 403' do
      [200, 401, 403].each do |code|
        let(:status) { code }

        its(:default_content_dir_exists?) { should be true }
      end
    end
  end

  describe '#content_dir=, #plugins_dir=' do
    ['wp-content', 'wp-custom'].each do |dir|
      context "when content_dir = #{dir} and no plugins_dir" do
        before { target.content_dir = dir }

        its(:content_dir) { should eq dir.chomp('/') }
        its(:plugins_dir) { should eq dir.chomp('/') + '/plugins' }
      end

      context "when content_dir = #{dir} and plugins_dir = #{dir}" do
        before do
          target.content_dir = dir
          target.plugins_dir = dir
        end

        its(:content_dir) { should eq dir.chomp('/') }
        its(:plugins_dir) { should eq dir.chomp('/') }
      end
    end
  end

  describe '#content_uri, #content_url, #plugins_uri, #plugins_url' do
    before { target.content_dir = 'wp-content' }

    its(:content_uri) { should eq Addressable::URI.parse("#{url}/wp-content/") }
    its(:content_url) { should eq "#{url}/wp-content/" }

    its(:plugins_uri) { should eq Addressable::URI.parse("#{url}/wp-content/plugins/") }
    its(:plugins_url) { should eq "#{url}/wp-content/plugins/" }
  end

  describe '#sub_dir' do
    { default: false, with_sub_dir: 'wp', relative_two_sub_dir: 'cms' }.each do |file, expected|
      it "returns #{expected} for #{file}.html" do
        fixture = File.join(fixtures, "#{file}.html")

        stub_request(:get, target.url).to_return(body: File.read(fixture))

        expect(target.sub_dir).to eql expected
      end
    end
  end

  describe '#url' do
    after { expect(target.url(@path)).to eql @expected }

    context 'when no path supplied' do
      it 'returns the target url' do
        @path     = nil
        @expected = "#{url}/"
      end
    end

    context 'when no sub_dir' do
      it 'does not add it' do
        expect(target).to receive(:sub_dir).and_return(false)

        @path     = 'something'
        @expected = "#{url}/#{@path}"
      end
    end

    context 'when sub_dir' do
      it 'adds it to the path' do
        expect(target).to receive(:sub_dir).at_least(1).and_return('wp')

        @path     = 'path'
        @expected = "#{url}/wp/path"
      end

      context 'when the path starts with /' do
        it 'does not add it' do
          @path     = '/root'
          @expected = "#{url}/root"
        end
      end
    end

    context 'when default directories' do
      before { target.content_dir = 'wp-content' }

      it 'does not replace the wp-content' do
        @path     = 'wp-content/themes/something'
        @expected = "#{url}/#{@path}"
      end
    end

    context 'when custom directories' do
      # Ensures non custom wp dir path are not replaced
      after do
        expect(target).to receive(:sub_dir).at_least(1).and_return(false)
        expect(target.url('not-wp-dir/spec.html')).to eql "#{url}/not-wp-dir/spec.html"
      end

      context 'when custom plugins dir' do
        before do
          target.content_dir = 'wp-content'
          target.plugins_dir = 'custom-plugins'
        end

        it 'replaces wp-content/plugins' do
          @path     = 'wp-content/plugins/p1/file.txt'
          @expected = "#{url}/custom-plugins/p1/file.txt"
        end

        it 'does not replace wp-content' do
          @path     = 'wp-content/themes/t1'
          @expected = "#{url}/wp-content/themes/t1"
        end
      end

      context 'when custom content dir' do
        before { target.content_dir = 'custom-content' }

        it 'replaces wp-content' do
          @path     = 'wp-content/plugins/p1'
          @expected = "#{url}/custom-content/plugins/p1"
        end
      end

      # Special case when for example, custom directories are
      # supplied by the user: the plugin dir can the default one,
      # but the content dir could be a custom (very rare case)
      context 'when custom content and default plugins directories' do
        before do
          target.content_dir = 'custom-content'
          target.plugins_dir = 'wp-content/plugins'
        end

        it 'does not replace wp-content/plugins ' do
          @path     = 'wp-content/plugins/p1/spec.html'
          @expected = "#{url}/#{@path}"
        end

        it 'replaces wp-content' do
          @path     = 'wp-content/themes/t1'
          @expected = "#{url}/custom-content/themes/t1"
        end
      end

      context 'when custom content and plugins directories' do
        before do
          target.content_dir = 'custom-content'
          target.plugins_dir = 'custom-plugins'
        end

        it 'replaces wp-content/plugins' do
          @path     = 'wp-content/plugins/p1/file.txt'
          @expected = "#{url}/custom-plugins/p1/file.txt"
        end

        it 'replaces wp-content' do
          @path     = 'wp-content/themes/t1'
          @expected = "#{url}/custom-content/themes/t1"
        end
      end
    end
  end
end
