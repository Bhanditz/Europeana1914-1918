##
# Abstract controller for federated searches.
#
class FederatedSearchController < ApplicationController
  before_filter :load_api_key
  before_filter :configured?
  before_filter :redirect_to_search, :only => :search
  
  class ResponseError < RuntimeError
    attr_reader :response
    
    def initialize(response)
      @response = response
    end
  end
  
  class << self
    # [String] Key to access the federated search's API, set in config/federated_search.yml
    attr_accessor :api_key
    
    # [String] URL to which API queries are sent
    attr_accessor :api_url
  end
  
  ##
  # Search action for a federated search.
  #
  # Sub-classes should route to the overriden method for their searches, and
  # call +super+ before the method end.
  #
  def search
    response = query_api(search_params)
    
    @query    = params[:q]
    @results  = response["results"]
    @facets   = response["facets"]
    
    respond_to do |format|
      format.html { render :template => 'search/page' }
      format.json { render :json => format_results_as_json }
    end
  end
  
  def show
    
  end
  
protected
  
  ##
  # Gets common search parameters with default values
  #
  def params_with_defaults
    @params_with_defaults ||= {
      :page   => (params[:page] || 1).to_i,
      :count  => [ (params[:count] || 48).to_i, 100 ].min, # Default 48, max 100
      :facets => params[:facets] || {}
    }
  end
  
  ##
  # Handles redirects to sanitize parameters.
  #
  # Sub-classes should:
  # * override this method
  # * alter the +params+ Hash as necessary
  # * perform their own tests for required redirects
  # * set +@redirect_required+ to +true+ if a redirect is required
  # * call +super+
  #
  def redirect_to_search
    if params[:provider] && params[:provider] != self.controller_name
      params.delete(:facets)
      params[:controller] = params[:provider]
      @redirect_required = true
    elsif params[:facets]
      params[:facets].each_key do |facet_name|
        if params[:facets][facet_name].is_a?(Array)
          params[:facets][facet_name] = params[:facets][facet_name].collect { |row| row.to_s }.join(",")
          @redirect_required = true
        end
      end
    end
    
    params.delete(:provider)
    
    redirect_to params if @redirect_required
  end
  
  ##
  # Gets the parameters to send to the federated search API
  #
  # When sub-classing, the returned +Hash+ should include the API key, query
  # terms, pagination settings, request for facets, and any other variables
  # required by the API.
  #
  # @return [Hash] Query parameters to send to the API
  #
  def search_params
    {}
  end
  
  ##
  # Gets the authentication params required by the API.
  #
  # Subclasses should implement this and return the params as a hash.
  #
  def authentication_params
    raise RuntimeError, "#authentication_params not implemented in #{self.class.name}"
  end
  
  ##
  # Validates response from API
  #
  # Sub-classes should implement this and raise a ResponseError if the response
  # from their respective API is invalid, i.e. does not contain results in the
  # expected format.
  #
  # @raise [ResponseError] if the response is invalid
  #
  def validate_response!(response)
    raise ResponseError.new(response) if response.nil?
  end
  
private

  ##
  # Sends the query to the API.
  #
  # @param [String] terms Text to search for
  # @return [Hash] Normalized API response, with keys "results" and "facets"
  #
  def query_api(params)
    url = construct_query_url(search_params)
    logger.debug("#{controller_name} API URL: #{url.to_s}")

    cache_key = "search/federated/#{controller_name}/" + Digest::MD5.hexdigest(url.to_s)
    if fragment_exist?(cache_key)
      response = YAML::load(read_fragment(cache_key))
    else
      response = JSON.parse(Net::HTTP.get(url))
      validate_response!(response)
      logger.debug("Federated search response: #{response.inspect}")
      write_fragment(cache_key, response.to_yaml, :expires_in => 1.day)
    end
    
    edm_results = edm_results_from_response(response)
    results = paginate_search_results(edm_results, params_with_defaults[:page], params_with_defaults[:count], total_entries_from_response(response))
    facets = facets_from_response(response)
    
    { "results" => results, "facets" => facets }
  rescue JSON::ParserError
    logger.error("ERROR: Unable to parse non-JSON response from #{controller_name} API query: #{url.to_s}")
    { "results" => [], "facets" => [] }
  rescue ResponseError => e
    logger.error("ERROR: Invalid response from #{controller_name} API query: #{e.response}")
    raise ResponseError.new(e.response), "Invalid response from #{controller_name} API: #{e.response}"
  end
  
  ##
  # Tests whether the federated search is configured.
  #
  # API keys should be set in config/federated_search.yml
  #
  # @raise [RuntimeError] if the federated search is not configured
  #
  def configured?
    raise RuntimeError, "Federated search \"#{controller_name}\" not configured." unless self.class.api_key.present?
  end
  
  ##
  # Formats the results as JSON based on Europeana API search response.
  #
  # Expects the following instance variables to be set:
  # * +@query+    => Query string entered by the user
  # * +@results+  => Paginated search results
  # * +@facets+   => Facets returned from the federated search
  #
  # @return [String] Formatted JSON response
  #
  def format_results_as_json
    json = {
      "success" => true,
      "itemsCount" => @results.size,
      "totalResults" => @results.total_entries,
      "items" => @results,
      "facets" => @facets,
      "params" => {
        "start" => @results.offset + 1,
        "query" => @query,
        "rows"  => @results.per_page
      }
    }.to_json
    
    jsonp = "#{params[:callback]}(#{json});" unless params[:callback].blank?
    
    jsonp || json
  end
  
  ##
  # Reads configuration for federated search APIs from config file
  #
  # @return [Hash] API keys for the active Rails env, keyed by controller/API name
  #
  def configuration
    path = File.join(::Rails.root, 'config', 'federated_search.yml')
    if File.exist?(path)
      File.open(path) do |file|
        processed = ERB.new(file.read).result
        YAML.load(processed)[Rails.env] || {}
      end
    else
      {}
    end
  end
  
  ##
  # Sets the API key class instance variable from the configuration file
  #
  def load_api_key
    self.class.api_key ||= configuration[controller_name]
  end
  
  ##
  # Constructs the URL for the API query
  #
  # @param [Hash] params Query parameters
  # @return [URI] URL to send the query to
  #
  def construct_query_url(params)
    url = URI.parse(self.class.api_url)
    url.query = params.to_query
    url
  end
  
  ##
  # Paginates search results for use with +will_paginate+
  #
  # @param results Search results from the API
  # @param [Fixnum] page Page of results currently displayed
  # @param [Fixnum] per_page Number of results displayed per page
  # @param [Fixnum] total Total number of results for this query
  # @return [WillPaginate::Collection] Paginated search results
  #
  def paginate_search_results(results, page, per_page, total)
    WillPaginate::Collection.create(page, per_page, total) do |pager|
      if total == 0
        pager.replace([])
      else
        pager.replace(results)
      end
    end
  end
end
