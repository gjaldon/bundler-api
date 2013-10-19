require 'rack/test'
require 'spec_helper'
require 'bundler_api/web'

describe BundlerApi::Web do
  include Rack::Test::Methods

  let(:builder) { GemBuilder.new($db) }
  let(:rack_id) { builder.create_rubygem("rack") }

  before do
    builder.create_version(rack_id, "rack")
  end

  def app
    BundlerApi::Web.new($db, $db)
  end

  context "GET /" do
    let(:request) { "/" }

    it "redirects to rubygems.org" do
      get request

      expect(last_response).to be_redirect
      expect(last_response.headers['Location']).
        to eq('https://www.rubygems.org')
    end
  end

  context "GET static files" do
    let(:request) { "/robots.txt" }

    it "redirects to rubygems.org" do
      get request
      expect(last_response).to be_ok
    end
  end

  context "GET nonexistent files'" do
    let(:request) { "/nonexistent" }

    it "redirects to rubygems.org" do
      get request
      expect(last_response).to be_not_found
    end
  end

  context "GET /api/v1/dependencies" do
    let(:request) { "/api/v1/dependencies" }

    context "there are no gems" do
      it "returns an empty string" do
        get request

        expect(last_response).to be_ok
        expect(last_response.body).to eq("")
      end
    end

    context "there are gems" do
      it "returns a marshal dump" do
        result = [{
          name:         'rack',
          number:       '1.0.0',
          platform:     'ruby',
          dependencies: []
        }]

        get "#{request}?gems=rack"

        expect(last_response).to be_ok
        expect(Marshal.load(last_response.body)).to eq(result)
      end
    end
  end


  context "GET /api/v1/dependencies.json" do
    let(:request) { "/api/v1/dependencies.json" }

    context "there are no gems" do
      it "returns an empty string" do
        get request

        expect(last_response).to be_ok
        expect(last_response.body).to eq("")
      end
    end

    context "there are gems" do
      it "returns a marshal dump" do
        result = [{
          "name"         => 'rack',
          "number"       => '1.0.0',
          "platform"     => 'ruby',
          "dependencies" => []
        }]

        get "#{request}?gems=rack"

        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)).to eq(result)
      end
    end
  end

  context "POST /api/v1/add_spec.json" do
    let(:url){ "/api/v1/add_spec.json" }
    let(:payload){ {:name => "rack", :version => "1.0.1",
      :platform => "ruby", :prerelease => false} }

    it "adds the spec to the database" do
      post url, JSON.dump(payload)

      expect(last_response).to be_ok
      res = JSON.parse(last_response.body)
      expect(res["name"]).to eq("rack")
      expect(res["version"]).to eq("1.0.1")
    end
  end

  context "POST /api/v1/remove_spec.json" do
    let(:url){ "/api/v1/remove_spec.json" }
    let(:payload){ {:name => "rack", :version => "1.0.0",
      :platform => "ruby", :prerelease => false} }

    it "removes the spec from the database" do
      post url, JSON.dump(payload)

      expect(last_response).to be_ok
      res = JSON.parse(last_response.body)
      expect(res["name"]).to eq("rack")
      expect(res["version"]).to eq("1.0.0")
    end
  end

  context "GET /quick/Marshal.4.8/:id" do
    it "redirects" do
      get "/quick/Marshal.4.8/rack"

      expect(last_response).to be_redirect
    end
  end

  context "GET /fetch/actual/gem/:id" do
    it "redirects" do
      get "/fetch/actual/gem/rack"

      expect(last_response).to be_redirect
    end
  end

  context "GET /gems/:id" do
    it "redirects" do
      get "/gems/rack"

      expect(last_response).to be_redirect
    end
  end

  context "/latest_specs.4.8.gz" do
    it "redirects" do
      get "/latest_specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/specs.4.8.gz" do
    it "redirects" do
      get "/specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/prerelease_specs.4.8.gz" do
    it "redirects" do
      get "/prerelease_specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/api/v2/names.list" do
    before do
      %w(a b c d).each {|gem_name| builder.create_rubygem(gem_name) }
    end

    it "returns an array" do
      get "/api/v2/names.list"

      expect(last_response).to be_ok
      expect(last_response.body).to eq(<<-NAMES.chomp.gsub(/^        /, ''))
        ---
        a
        b
        c
        d
        rack
      NAMES
    end
  end

  context "/api/v2/versions.list" do
    before do
      {
        "a" => ["1.0.0", "1.0.1"],
        "b" => ["1.0.0"],
        "c" => ["1.0.0-java"]
      }.each do |gem_name, versions|
        gem_id = builder.create_rubygem(gem_name)
        versions.each do |full_version|
          version, platform = full_version.split('-', 2)
          platform = 'ruby' unless platform
          builder.create_version(gem_id, gem_name, version, platform)
        end
      end
    end

    let(:expected_output) { <<-VERSIONS.gsub(/^          /, '')
          ---
          a 1.0.0,1.0.1
          b 1.0.0
          c 1.0.0-java
          rack 1.0.0
        VERSIONS
    }
    let(:expected_etag) { Digest::MD5.hexdigest(expected_output) }

    it "returns versions.list" do
      get "/api/v2/versions.list"

      expect(last_response).to be_ok
      expect(last_response.header["ETag"]).to eq(expected_etag)
      expect(last_response.body).to eq(expected_output)
    end

    it "should return 304 on second hit" do
      get "/api/v2/versions.list"
      etag = last_response.header["ETag"]

      get "/api/v2/versions.list", {}, "HTTP_If-None-Match" => etag

      expect(last_response.status).to eq(304)
    end
  end

  context "/api/v2/deps/:gem" do
    before do
      rack_101 = builder.create_version(rack_id, 'rack', '1.0.1')
      [['foo', '= 1.0.0'], ['bar', '>= 2.1, < 3.0']].each do |dep, requirements|
        dep_id = builder.create_rubygem(dep)
        builder.create_dependency(dep_id, rack_101, requirements)
      end
    end

    let(:expected_deps) {
      <<-DEPS.gsub(/^        /, '')
        ---
        1.0.0
        1.0.1 bar:>= 2.1&< 3.0,foo:= 1.0.0
      DEPS
    }
    let(:expected_etag) { Digest::MD5.hexdigest(expected_deps) }

    context "client does not have an ETag" do
      it "should return the gem list" do
        get "/api/v2/deps/rack"

        expect(last_response).to be_ok
        expect(last_response.header["ETag"]).to eq(expected_etag)
        expect(last_response.body).to eq(expected_deps)
      end

      it "should return 304 on second hit" do
        get "/api/v2/deps/rack"

        get "/api/v2/deps/rack", {}, "HTTP_If-None-Match" => expected_etag

        expect(last_response.status).to eq(304)
      end
    end

    context "client already has an ETag" do
      before do
        $db[:rubygems].where(id: rack_id).update(deps_md5: expected_etag)
      end

      it "should return a 304 if the ETag is the same" do
        get "/api/v2/deps/rack", {}, "HTTP_If-None-Match" => expected_etag

        expect(last_response.status).to eq(304)
      end
    end
  end
end
