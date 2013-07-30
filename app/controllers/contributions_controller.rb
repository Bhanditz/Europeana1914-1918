# set search result defaults in the #search method
class ContributionsController < ApplicationController
  before_filter :find_contribution, 
    :except => [ :index, :new, :create, :search, :explore, :complete ]
  before_filter :redirect_to_search, :only => :search

  cache_sweeper :contribution_sweeper, :only => [ :create, :update, :destroy ]

  # GET /contributions
  def index
    if RunCoCo.configuration.publish_contributions?
      search
    else
      @contributions = []
    end
  end

  # GET /contributions/new
  def new
    current_user.may_create_contribution!
    @contribution = Contribution.new
    if current_user.may_catalogue_contributions? && @contribution.catalogued_by.blank?
      @contribution.catalogued_by = current_user.id
    end
  end

  # POST /contributions
  def create
    if (current_user.role.name == 'guest') && !RunCoCo.configuration.registration_required?
      if session[:guest][:contribution_id].present?
        redirect_to edit_contribution_path(session[:guest][:contribution_id])
        return
      elsif session[:guest][:contact_id].blank?
        redirect_to new_contributor_guest_path
        return
      end
    end
    current_user.may_create_contribution!
    
    @contribution = Contribution.new 
    if current_user.may_catalogue_contributions?
      @contribution.catalogued_by = params[:contribution].delete(:catalogued_by)
    end
    @contribution.attributes = params[:contribution]

    if current_user.role.name == 'guest'
      @contribution.guest = current_user.contact
    else
      @contribution.contributor = current_user
    end
    
    if @contribution.save
      if current_user.role.name == 'guest'
        session[:guest][:contribution_id] = @contribution.id
      end
      flash[:notice] = t('flash.contributions.draft.create.notice')
      redirect_to new_contribution_attachment_path(@contribution)
    else
      RunCoCo.error_logger.debug("Contribution creation failed: #{@contribution.errors.inspect}")
      flash[:alert] = t('flash.contributions.draft.create.alert')
      render :action => 'new'
    end
  end

  # GET /contributions/:id
  def show
    current_user.may_view_contribution!(@contribution)
    if @contribution.draft? && current_user.may_edit_contribution?(@contribution)
      redirect_to edit_contribution_path(@contribution) and return
    end
    @attachments = @contribution.attachments.paginate(:page => params[:page], :per_page => params[:count] || 3 )
    
    respond_to do |format|
      format.json  { render :json => { :result => 'success', :object => @contribution.to_rdf_graph.dump(:json) } } 
      format.html
      format.nt { render :text => @contribution.to_ntriples }
      format.xml { render :xml => @contribution.to_rdfxml }
    end
  end
  
  # GET /contributions/:id/status_log
  def status_log
    current_user.may_view_contribution_status_log!(@contribution)
  end

  # GET /contributions/:id/edit
  def edit
    current_user.may_edit_contribution!(@contribution)
    
    if current_user.may_catalogue_contributions?
      @contribution.metadata.cataloguing = true
      if @contribution.catalogued_by.blank?
        @contribution.catalogued_by = current_user.id
      end
    end
  end

  # PUT /contributions/:id
  def update
    current_user.may_edit_contribution!(@contribution)

    if current_user.may_catalogue_contributions? && @contribution.catalogued_by.blank?
      @contribution.catalogued_by = params[:contribution].delete(:catalogued_by)
    end
    @contribution.attributes = params[:contribution]
    if current_user.may_catalogue_contributions?
      @contribution.metadata.cataloguing = true
    end

    if @contribution.save
      # Updates made by non-cataloguers change the contribution's status to
      # :revised
      if !current_user.may_catalogue_contributions? && (@contribution.status == :approved)
        @contribution.change_status_to(:revised, current_user.id)
      end
      flash[:notice] = t('flash.contributions.draft.update.notice')
      redirect_to (@contribution.draft? ? new_contribution_attachment_path(@contribution) : @contribution)
    else
      flash.now[:alert] = t('flash.contributions.draft.update.alert')
      render :action => 'edit'
    end
  end
  
  # PUT /contributions/:id/submit
  def submit
    current_user.may_edit_contribution!(@contribution)
    if @contribution.submit
      if current_user.role.name == 'guest'
        session[:guest].delete(:contribution_id)
      end
      redirect_to complete_contributions_url
    else
      flash.now[:alert] = t('flash.contributions.draft.submit.alert')
    end
  end
  
  # PUT /contributions/:id/approve
  def approve
    current_user.may_approve_contributions!
    if @contribution.approve_by(current_user)
      if @contribution.statuses.select { |s| s.to_sym == :approved }.size == 1
        email = @contribution.by_guest? ? @contribution.contact.email : @contribution.contributor.email
        if email.present?
          ContributionsMailer.published(email, @contribution).deliver
        end
      end
      flash[:notice] = t('flash.contributions.approve.notice')
      redirect_to admin_contributions_url
    else
      @show_errors = true
      flash.now[:alert] = t('flash.contributions.approve.alert')
      @attachments = @contribution.attachments.paginate(:page => params[:page], :per_page => params[:count] || 3 )
      render :action => 'show'
    end
  end
  
  # PUT /contributions/:id/reject
  def reject
    current_user.may_reject_contributions!
    if @contribution.reject_by(current_user)
      flash[:notice] = t('flash.contributions.reject.notice')
      redirect_to admin_contributions_url
    else
      @show_errors = true
      flash.now[:alert] = t('flash.contributions.reject.alert')
      @attachments = @contribution.attachments.paginate(:page => params[:page], :per_page => params[:count] || 3 )
      render :action => 'show'
    end
  end
  
  # GET /contributions/search?q=:q
  def search
    current_user.may_search_contributions!
    
    @count = per_page = [ (params[:count] || 48).to_i, 100 ].min
    search_options = { :page => params[:page] || 1, :per_page => per_page, :contributor_id => params[:contributor_id], :facets => params[:facets] }
    
    # Uncomment for minimal eager loading of associations to optimize performance
    # when search result partials are not pre-cached.
    #search_options[:include] = [ :attachments, :metadata ]
    
    if params[:field_name] && params[:term]
      @term = CGI::unescape(params[:term])
      @field = MetadataField.find_by_name!(params[:field_name])
      
      if taxonomy_term = @field.taxonomy_terms.find_by_term(@term)
        search_options[:taxonomy_term] = taxonomy_term
      else
        search = [] # Prevent search from running if field not found
      end
    else
      @query = params[:q]
      search_query = bing_translate(@query)
    end
    
    if search.nil?
      search = Contribution.search(:published, search_query, search_options)
    end
    
    @results = @contributions = search.results
    @facets = search.respond_to?(:facets) ? search.facets : nil

    if params.delete(:layout) == '0'
      render :partial => '/search/results',
        :locals => {
          :contributions => @contributions,
          :results => @results,
          :query => @query,
          :term => @term
        } and return
    end
    
    render :template => 'search/page'
  end
  
  # GET /explore/:field_name/:term
  def explore
    search
  end
  
  # GET /contributions/:id/delete
  def delete
    current_user.may_delete_contribution!(@contribution)
  end

  # DELETE /contributions/:id
  def destroy
    current_user.may_delete_contribution!(@contribution)
    if @contribution.destroy
      if current_user.role.name == 'guest'
        session[:guest].delete(:contribution_id)
      end
        
      flash[:notice] = t('flash.contributions.destroy.notice')
      redirect_to ((current_user.role.name == 'administrator') ? admin_contributions_url : contributor_dashboard_url)
    else
      flash.now[:alert] = t('flash.contributions.destroy.alert')
      render :action => 'delete'
    end
  end
  
  # GET /contributions/:id/withdraw
  def withdraw
    current_user.may_withdraw_contribution!(@contribution)
  end
  
  # PUT /contributions/:id/withdraw
  def set_withdrawn
    current_user.may_withdraw_contribution!(@contribution)
    if @contribution.change_status_to(:withdrawn)
      flash[:notice] = t('flash.contributions.withdraw.notice')
      redirect_to contributor_dashboard_url
    else
      flash.now[:alert] = t('flash.contributions.withdraw.alert')
      render :action => 'withdraw'
    end
  end

protected

  def find_contribution
    @contribution = Contribution.find(params[:id], :include => [ :contributor, :attachments, :metadata ])
  end
  
  def redirect_to_search
    unless params[:qf].blank?
      params.merge!(:q => params[:q] + " " + params[:qf])
      params.delete(:qf)
      redirect_required = true
    end
    
    if params[:provider] == 'europeana'
      params.delete(:facets)
      params[:controller] = 'europeana'
      redirect_required = true
    elsif params[:facets]
      params[:facets].each_key do |facet_name|
        if params[:facets][facet_name].is_a?(Array)
          params[:facets][facet_name] = params[:facets][facet_name].collect { |row| row.to_s }.join(",")
          redirect_required = true
        end
      end
    end
    
    params.delete(:provider)
    
    redirect_to params if redirect_required
  end

end

