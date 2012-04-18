# Contribution consisiting of files and metadata.
class Contribution < ActiveRecord::Base
  belongs_to :contributor, :class_name => 'User'
  belongs_to :cataloguer, :class_name => 'User', :foreign_key => 'catalogued_by'
  belongs_to :metadata, :class_name => 'MetadataRecord', :foreign_key => 'metadata_record_id', :dependent => :destroy
  #--
  # FIXME: Destroy associated contact when contribution destroyed, *IF* this is a guest contribution, *AND* there are no other associated contributions
  #++
  belongs_to :guest
  belongs_to :current_status, :class_name => 'ContributionStatus'

  has_many :attachments, :class_name => '::Attachment', :dependent => :destroy, :include => :metadata do
    def with_file
      select { |attachment| attachment.file.present? }
    end

    def to_json(options = nil)
      proxy_owner.attachments.collect { |a| a.to_hash }.to_json(options)
    end
  end
  
  has_many :statuses, :class_name => 'ContributionStatus', :dependent => :destroy, :order => 'created_at ASC'
  
  accepts_nested_attributes_for :metadata

  validates_presence_of :contributor_id, :if => Proc.new { RunCoCo.configuration.registration_required? }
  validates_presence_of :title
  validates_associated :metadata

  validate :validate_contributor_or_contact, :unless => Proc.new { RunCoCo.configuration.registration_required? }
  validate :validate_attachment_file_presence, :if => :submitting?
  validate :validate_cataloguer_role, :if => Proc.new { |c| c.catalogued_by.present? }

  attr_accessible :metadata_attributes, :title

  after_create :create_draft_status
  
  after_initialize :build_metadata_unless_present

  # Trigger syncing of public status of attachments to contribution's
  # published status.
  after_save do |c|
    c.attachments.each do |a|
      a.set_public
      a.save
    end
  end

  # Number of contributions to show per page when paginating
  cattr_reader :per_page
  @@per_page = 20

  # Dynamically define Sphinx search index.
  #
  # MetadataRecord columns equivalent to MetadataField records flagged
  # as searchable will be indexed.
  def self.set_search_index
    define_index_str = "define_index do\n"
    define_index_str << "  set_property :delta => true\n"
    define_index_str << "  indexes title, :sortable => true\n"
    define_index_str << "  indexes contributor.contact.full_name, :sortable => true, :as => :contributor\n"
    # This next one is a hack to ensure subsequent has/indexes calls for
    # taxonomy terms always get aliased table names.
    define_index_str << "  indexes metadata.null_taxonomy_terms.term, :as => :null_taxonomy_terms\n"
    define_index_str << "  has created_at\n"
    define_index_str << "  has current_status.status, :as => :status\n"
    define_index_str << "  has current_status.created_at, :as => :status_timestamp\n"

    fields = MetadataField.where('(searchable = ? OR facet = ?)', true, true)
    unless fields.count == 0
      fields.each do |field|
        index_alias = "metadata_#{field.name}"
        indexes_or_has = field.searchable? ? 'indexes' : 'has'
        facet = field.facet? ? 'true' : 'false'
        if field.field_type == 'taxonomy'
          define_index_str << "  #{indexes_or_has} metadata.field_#{field.name}_terms.term, :sortable => true, :as => :#{index_alias}, :facet => #{facet}\n"
        else
          define_index_str << "  #{indexes_or_has} metadata.#{MetadataRecord.column_name(field)}, :sortable => true, :as => :#{index_alias}, :facet => #{facet}\n"
        end
      end
    end
    
    define_index_str << "end\n"

    class_eval(define_index_str, __FILE__, __LINE__)
  end
  set_search_index

  def contact
    by_guest? ? guest : contributor.contact
  end
  
  def by_guest?
    contributor.blank?
  end

  ##
  # Returns a symbol describing this contribution's status
  #
  # Return value will be one of:
  # * :draft
  # * :submitted
  # * :approved
  # * :rejected
  # * :unknown
  #
  # @return [Symbol] The contribution's current status
  # @see ContributionStatus.to_sym
  #
  def status
    current_status.nil? ? nil : current_status.to_sym
  end

  ##
  # Submits the contribution for approval.
  #
  # Creates a {ContributionStatus} record with status = 
  # {ContributionStatus::SUBMITTED}.
  #
  # @return [Boolean] True if {ContributionStatus} record saved.
  #
  def submit
    @submitting = true
    if valid?
      status = ContributionStatus.create(:contribution_id => id, :user_id => contributor_id, :status => ContributionStatus::SUBMITTED)
      status.id.present?
    else
      false
    end
  end
  
  def submitting?
    @submitting == true
  end

  def submitted?
    status == :submitted
  end

  def ready_to_submit?
    if @ready_to_submit.nil?
      if !draft? || attachments.blank?
        @ready_to_submit = false
      else
        valid?
        validate_attachment_file_presence
        @ready_to_submit = self.errors.blank?
      end
    end
    @ready_to_submit
  end
  
  def draft?
    status == :draft
  end

  def approved?
    status == :approved
  end

  def approve_by(approver)
    metadata.cataloguing = true
    if valid?
      status = ContributionStatus.create(:contribution_id => id, :user_id => approver.id, :status => ContributionStatus::APPROVED)
      status.id.present?
    else
      false
    end
  end
  
  def rejected?
    status == :rejected
  end

  def reject_by(rejecter)
    status = ContributionStatus.create(:contribution_id => id, :user_id => rejecter.id, :status => ContributionStatus::REJECTED)
    status.id.present?
  end
  
  def published?
    if !RunCoCo.configuration.publish_contributions
      false
    else
      if RunCoCo.configuration.contribution_approval_required
        status == :approved
      else
        status == :submitted
      end
    end
  end
  
  def validate_contributor_or_contact
    if self.contributor_id.blank? && self.guest_id.blank?
      self.errors.add(:guest_id, I18n.t('activerecord.errors.models.contribution.attributes.guest_id.present'))
    end
  end
  
  def validate_attachment_file_presence
    self.errors.add(:base, I18n.t('views.contributions.digital_object.help_text.add_attachment')) unless attachments.with_file.count == attachments.count
  end
  
  def validate_cataloguer_role
    self.errors.add(:catalogued_by, I18n.t('activerecord.errors.models.contribution.attributes.catalogued_by.role_name')) unless [ 'administrator', 'cataloguer' ].include?(User.find(catalogued_by).role_name)
  end
  
  alias :"rails_metadata_attributes=" :"metadata_attributes="
  def metadata_attributes=(*args)
    self.send(:"rails_metadata_attributes=", *args)
    self.metadata.for_contribution = true
  end
  
  alias :rails_build_metadata :build_metadata
  def build_metadata(*args)
    rails_build_metadata(*args)
    self.metadata.for_contribution = true
  end
    
  ##
  # Fetches and yields approved & published contributions for export.
  #
  # @example
  #   Contribution.export(:batch_size => 50) do |contribution|
  #     puts contribution.title
  #   end
  #
  # @param [Hash] options Export options
  # @option options [String] :exclude Exclude attachment records with files 
  #   having this extension
  # @option options [DateTime] :start_date only yield contributions published 
  #   on or after this date & time
  # @option options [DateTime] :end_date only yield contributions published on 
  #   or before this date & time
  # @option options [Integer] :batch_size (50) export in batches of this size; 
  #   passed to {#find_each}
  # @yieldreturn [Contribution] exported contributions
  def self.export(options)
    options.assert_valid_keys(:exclude, :start_date, :end_date, :batch_size)
    options.reverse_merge!(:batch_size => 50)
    
    if options[:exclude].present?
      ext = options[:exclude].exclude
      unless ext[0] == '.'
        ext = '.' + ext
      end
    end
    
    if RunCoCo.configuration.contribution_approval_required
      conditions = [ 'contribution_statuses.status=?', ContributionStatus::APPROVED ]
    else
      conditions = [ 'contribution_statuses.status=?', ContributionStatus::SUBMITTED ]
    end
    
    if options[:start_date].present?
      conditions[0] << ' AND contribution_statuses.created_at >= ?'
      conditions << options[:start_date]
    end
    
    if options[:end_date].present?
      conditions[0] << ' AND contribution_statuses.created_at <= ?'
      conditions << options[:end_date]
    end
    
    includes = [ 
      { :attachments => { :metadata => :taxonomy_terms } }, 
      { :metadata => :taxonomy_terms }, 
      { :contributor => :contact },
      :current_status
    ]
    
    Contribution.find_each(
      :conditions => conditions,
      :include => includes,
      :batch_size => options[:batch_size]
    ) do |contribution|
    
      if options[:exclude]
        contribution.attachments.reject! do |a|
          File.extname(a.file.path) == ext
        end
      end
    
      yield contribution
    end
  end
  
  protected
  def build_metadata_unless_present
    self.build_metadata unless self.metadata.present?
  end
  
  ##
  # Creates a {ContributionStatus} record with status = 
  # {ContributionStatus::DRAFT}
  #
  def create_draft_status
    ContributionStatus.create!(:contribution_id => id, :user_id => contributor_id, :status => ContributionStatus::DRAFT)
  end
end

