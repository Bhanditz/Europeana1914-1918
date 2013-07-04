module ContributionSearch
  module Solr
    ##
    # Tests if Solr server is accessible by attempting an HTTP connection to it.
    #
    # @return [Boolean]
    #
    def self.solr_accessible?
      Net::HTTP.get(URI(Sunspot.config.solr.url))
      true
    rescue Errno::ECONNREFUSED
      false
    end
  
    def self.included(base)
      base.class_eval do
        include ContributionSearch
        include ContributionSearch::ActiveRecord
        
        if ContributionSearch::Solr.solr_accessible?
        
          # Set up the Solr index
          searchable do
            text    :title
            text    :contributor do
              contributor.contact.full_name
            end
            
            integer :contributor_id
            integer :metadata_record_id
            integer :current_status
            
            time    :created_at
            time    :status_timestamp
            
            # Index all searchable taxonomy terms at once
            text    :taxonomy_terms do
              metadata.searchable_taxonomy_terms.collect { |t| t.term }
            end
            integer :taxonomy_term_ids, :multiple => true do
              metadata.searchable_taxonomy_terms.collect { |t| t.id }
            end
            
            # Index other searchable fields individually
            fields = MetadataField.where('(searchable = ? OR facet = ?) AND field_type <> ?', true, true, 'taxonomy')
            unless fields.count == 0
              fields.each do |field|
                text "metadata_#{field.name}" do
                  metadata.send(MetadataRecord.column_name(field.name))
                end
              end
            end
            
            # Facets
            MetadataField.where(:facet => true, :field_type => 'taxonomy').each do |field|
              integer "metadata_#{field.name}_ids", :multiple => true do
                metadata.send("field_#{field.name}_term_ids")
              end
            end
            
            string "protagonist_names", :multiple => true do
              [ '1', '2' ].collect do |cnum|
                [ metadata.send("field_character#{cnum}_given_name"), metadata.send("field_character#{cnum}_family_name") ].join(' ')
              end.reject { |cname| cname.blank? || cname == '' }
            end
          end
          
          base.extend(ClassMethods)
        end
      end
    end
    
    module ClassMethods
      ##
      # Run a search against Solr index
      #
      # Search against contribution titles and any metadata fields flagged as
      # searchable.
      #
      # @param (see ContributionSearch::ClassMethods#search)
      # @return (see ContributionSearch::ClassMethods#search)
      # @todo Configurable max matches
      #
      def search(set, query = nil, options = {})
        assert_valid_set(set)
        
        solr_options = options.dup
        
        solr_search do
          unless set.nil?
            if set == :published
              with :current_status, ContributionStatus.published
            else
              with :current_status, ContributionStatus.const_get(set.to_s.upcase)
            end
          end
          
          if contributor_id = solr_options.delete(:contributor_id)
            with :contributor_id, contributor_id
          end
          
          if taxonomy_term = solr_options.delete(:taxonomy_term)
            with :taxonomy_term_ids, taxonomy_term.id
          end
          
          if order = solr_options.delete(:order)
            order = order.downcase.to_sym
            order = :asc unless [ :desc, :asc ].include?(order)
          end
          
          if facets = solr_options.delete(:facets)
            facets.each_pair do |name, criterion|
              with name.to_sym, criterion.to_i
            end
          end
        
          if sort = solr_options.delete(:sort)
            if MetadataRecord.taxonomy_associations.include?(sort.to_sym)
              sort_col = nil
            elsif sort =~ /^field_/
              # Convert field name to index alias
              sort_col = sort.sub(/^field_/, 'metadata_')
            else
              sort_col = sort
            end
            
            order_by(sort_col.to_sym, order) unless sort_col.nil?
          else
            if set == :submitted
              order_by(:status_timestamp, :asc)
            else
              order_by(:status_timestamp, :desc)
            end
          end
          
          paginate(:page => solr_options[:page], :per_page => solr_options[:per_page])
          
          unless query.blank?
            if query.is_a?(Hash)
              query_string = query.dup.values.uniq.add_quote_marks.join(' ')
            else
              query_string = query
            end
            fulltext query_string, { :minimum_match => 1 } # Equivalent to Boolean OR in dismax query mode
          end
          
          MetadataField.where(:facet => true, :field_type => 'taxonomy').each do |field|
            facet "metadata_#{field.name}_ids"
          end
          facet "protagonist_names"
        end
      rescue Errno::ECONNREFUSED
        RunCoCo.error_logger.warn('Solr not accessible; falling back to ActiveRecord search.')
        active_record_search(set, query, options)
      end
    end
  end
end
