require "spec_helper"

module VCAP::CloudController
  describe AppSummariesController do
    describe "GET /v2/apps/:id/summary" do
      let(:app1) { App.make }

      describe "user from token" do
        it "security context is set to user obtained from the token" do
          token_to_user_finder = instance_double("VCAP::CloudController::TokenToUserFinder")
          CloudController::DependencyLocator.instance.stub(:token_to_user_finder).
            with(no_args).
            and_return(token_to_user_finder)

          user = instance_double("VCAP::CloudController::User")
          token = double('token')
          expect(token_to_user_finder).to receive(:find).
            with("fake-token").
            and_return([user, token])

          expect(SecurityContext).to receive(:set).with(user, token)
          get "/v2/apps/#{app1.guid}/summary", {}, admin_headers.merge("HTTP_AUTHORIZATION" => "fake-token") rescue nil
        end
      end

      describe "request sheme verification" do
        it "handles the invalid request scheme" do
          request_scheme_verifier = instance_double("VCAP::CloudController::RequestSchemeVerifier")
          CloudController::DependencyLocator.instance.stub(:request_scheme_verifier).
            with(no_args).
            and_return(request_scheme_verifier)

          exception = Exception.new
          request_scheme_verifier.should_receive(:verify).
            with(kind_of(Rack::Request), SecurityContext).
            and_raise(exception)

          response_exception_handler = instance_double("VCAP::CloudController::ResponseExceptionHandler")
          CloudController::DependencyLocator.instance.stub(:response_exception_handler).
            with(no_args).
            and_return(response_exception_handler)

          response_exception_handler.should_receive(:handle).
            with(kind_of(ActionDispatch::Response), exception)

          get "/v2/apps/#{app1.guid}/summary", {}, admin_headers
        end
      end

      context "when app does not exist" do
        it "returns 404" do
          get "/v2/apps/fake-not-found-guid/summary", {}, admin_headers
          expect_api_error(last_response, {
            code: 100004,
            response_code: 404,
            description: "The app name could not be found: fake-not-found-guid",
            error_code: "CF-AppNotFound",
            types: ["AppNotFound", "Error"],
          })
        end
      end

      context "when app exists" do
        before do
          locator = CloudController::DependencyLocator.instance
          locator.stub(:authorization_provider).with(no_args).and_return(test_auth_provider)
        end
        let(:test_auth_provider) { Authorization::SingleOpProvider.new }

        context "when can access the app" do
          before { test_auth_provider.allow_access(:read, app1) }

          it "present full obj" do
            get "/v2/apps/#{app1.guid}/summary", {}, admin_headers
            expect(last_response.status).to eq(200)
          end
        end

        context "when cannot access the app" do
          it "has an error response" do
            get "/v2/apps/#{app1.guid}/summary", {}, admin_headers
            expect_api_error(last_response, {
              code: 10003,
              response_code: 403,
              description: "You are not authorized to perform the requested action",
              error_code: "CF-NotAuthorized",
              types: ["NotAuthorized", "Error"],
            })
          end
        end
      end

      def expect_api_error(response, expected)
        expect(response.status).to eq(expected.fetch(:response_code))

        decoded_response = parse(response.body)
        expect(decoded_response.keys).to match_array(
          ["code", "description", "error_code", "types", "backtrace"])
        expect(decoded_response["code"]).to eq(expected.fetch(:code))
        expect(decoded_response["description"]).to eq(expected.fetch(:description))
        expect(decoded_response["error_code"]).to eq(expected.fetch(:error_code))
        expect(decoded_response["types"]).to eq(expected.fetch(:types))
      end
    end

    #before do
    #  @num_services = 2
    #  @free_mem_size = 128
    #
    #  @shared_domain = SharedDomain.make
    #  @shared_domain.save
    #
    #  @space = Space.make
    #  @route1 = Route.make(:space => @space)
    #  @route2 = Route.make(:space => @space)
    #  @services = []
    #
    #  @app = AppFactory.make(
    #    :space => @space,
    #    :production => false,
    #    :instances => 1,
    #    :memory => @free_mem_size,
    #    :state => "STARTED",
    #    :package_hash => "abc",
    #    :package_state => "STAGED"
    #  )
    #
    #  @num_services.times do
    #    instance = ManagedServiceInstance.make(:space => @space)
    #    @services << instance
    #    ServiceBinding.make(:app => @app, :service_instance => instance)
    #  end
    #
    #  @app.add_route(@route1)
    #  @app.add_route(@route2)
    #end
    #
    #describe "GET /v2/apps/:id/summary" do
    #  before do
    #    health_manager_client = CloudController::DependencyLocator.instance.health_manager_client
    #    health_manager_client.should_receive(:healthy_instances).and_return(@app.instances)
    #    get "/v2/apps/#{@app.guid}/summary", {}, admin_headers
    #  end
    #
    #  it "should return 200" do
    #    last_response.status.should == 200
    #  end
    #
    #  it "should return the app guid" do
    #    decoded_response["guid"].should == @app.guid
    #  end
    #
    #  it "should return the app name" do
    #    decoded_response["name"].should == @app.name
    #  end
    #
    #  it "should return the app routes" do
    #    decoded_response["routes"].should == [{
    #      "guid" => @route1.guid,
    #      "host" => @route1.host,
    #      "domain" => {
    #        "guid" => @route1.domain.guid,
    #        "name" => @route1.domain.name
    #      }
    #    }, {
    #      "guid" => @route2.guid,
    #      "host" => @route2.host,
    #      "domain" => {
    #        "guid" => @route2.domain.guid,
    #        "name" => @route2.domain.name}
    #    }]
    #  end
    #
    #  it "should contain the running instances" do
    #    decoded_response["running_instances"].should == @app.instances
    #  end
    #
    #  it "should contain the basic app attributes" do
    #    @app.to_hash.each do |k, v|
    #      v.should eql(decoded_response[k.to_s]), "value of field #{k} expected to eql #{v}"
    #    end
    #  end
    #
    #  it "should contain list of both private domains and shared domains" do
    #    domains = @app.space.organization.private_domains
    #    expect(domains.count > 0).to eq(true)
    #
    #    private_domains = domains.collect do |domain|
    #      { "guid" => domain.guid,
    #        "name" => domain.name,
    #        "owning_organization_guid" =>
    #          domain.owning_organization.guid
    #      }
    #    end
    #
    #    shared_domains = SharedDomain.all.collect do |domain|
    #      { "guid" => domain.guid,
    #        "name" => domain.name,
    #      }
    #    end
    #
    #    decoded_response["available_domains"].should =~ (private_domains + shared_domains)
    #  end
    #
    #  it "should return correct number of services" do
    #    decoded_response["services"].size.should == @num_services
    #  end
    #
    #  it "should return the correct info for a service" do
    #    svc_resp = decoded_response["services"][0]
    #    svc = @services.find { |s| s.guid == svc_resp["guid"] }
    #
    #    svc_resp.should == {
    #      "guid" => svc.guid,
    #      "name" => svc.name,
    #      "bound_app_count" => 1,
    #      "dashboard_url" => svc.dashboard_url,
    #      "service_plan" => {
    #        "guid" => svc.service_plan.guid,
    #        "name" => svc.service_plan.name,
    #        "service" => {
    #          "guid" => svc.service_plan.service.guid,
    #          "label" => svc.service_plan.service.label,
    #          "provider" => svc.service_plan.service.provider,
    #          "version" => svc.service_plan.service.version,
    #        }
    #      }
    #    }
    #  end
    #end
  end
end
