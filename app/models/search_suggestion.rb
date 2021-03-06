##
# Model storing common words from the Sphinx search index.
#
# Used for auto-complete functionality on the collection search form.
#
class SearchSuggestion < ActiveRecord::Base
  # Minimum length of word to index and return as an auto-complete suggestion.
  # Needs to be 1 for phrase searches to work.
  # [Only relevant if Sphinx used to index and search this model's db table.]
  #mattr_accessor :min_prefix_length
  #self.min_prefix_length = 1
  
  # Only suggest words/phrases with a minimum of this length
  mattr_accessor :min_word_length
  self.min_word_length = 3
  
  # Maximum number of suggestions to return in one query
  mattr_accessor :max_matches
  self.max_matches = 30
  
  # Minimum frequency for words/phrases to be stored as a suggestion
  mattr_accessor :min_frequency
  self.min_frequency = 5
  
  # Default number of stop words to extract from main contribution search index
  # when using the rake task "auto_complete:stops:generate". Can be overriden
  # with the COUNT environment variable.
  mattr_accessor :max_stops
  self.max_stops = 1000
  
  validates_presence_of :text
  validates_uniqueness_of :text, :case_sensitive => false
  validates_length_of :text, :minimum => self.min_word_length
  validates_format_of :text, :without => /^\d+$/ # Ignore numbers
  validates_inclusion_of :stop_word, :in => [ true, false ]
  validates_numericality_of :frequency, :greater_than_or_equal_to => self.min_frequency
  
  ##
  # Populates the table from a Sphinx stop words file.
  #
  # This method will delete from the database all stop word entries
  # (flagged by the {#stop_word} attribute) not in the stop word file, 
  # update the frequency of those that are already in the db, and insert 
  # records for any new ones.
  #
  # This can be triggered from the command-line using the Rake task:
  #   bundle exec rake auto_complete:stops:import
  #
  # The stop words file is a plain text file with one word per line, as
  # generated by the Sphinx `indexer` binary when run with the --buildstops
  # option. A Rake task is provided to generate this file for local Sphinx
  # installations: 
  #   bundle exec rake auto_complete:stops:generate
  #
  # If frequencies are included in the stop words file as the second file,
  # separated by a space, they will be stored to the {#frequency} attribute.
  # Frequencies can be generated in the Sphinx stop words file with the
  # --buildfreqs option.
  #
  # @param [String] path Path to the stop words file
  # @return [Fixnum] Resulting number of stop word records in the database
  #
  def self.from_stop_words_file!(path)
    raise Exception, "Stop words file \"#{path}\" not found" unless File.exists?(path)
    
    stop_word_freqs = {}
    File.open(path, "r").each do |line|
      line.sub!(Regexp.new("#{$/}$"), '') # Remove line separator
      word, freq = line.split(' ')
      stop_word_freqs[word] = freq.to_i
    end
    
    # Get rid of those that will fail validation.
    # (Much faster than going to ActiveModel::Validations)
    stop_word_freqs.reject! do |phrase, freq|
      (phrase.length < self.min_word_length) || (freq < self.min_frequency) || phrase.match(/^\d+$/)
    end
    
    lower_words = stop_word_freqs.keys.collect { |word| word.downcase }
    existing_word_freqs = {}

    self.where(:stop_word => true).find_each do |word|
      if lower_words.include?(word.text)
        existing_word_freqs[word.text] = word.frequency
      else
        word.destroy
      end
    end
    
    stop_word_freqs.each_pair do |word, freq|
      if existing_word_freqs.has_key?(word)
        unless existing_word_freqs[word] == freq
          self.update_all({ :frequency => freq }, { :stop_word => true, :text => word })
        end
      else
        self.create(:text => word, :frequency => freq, :stop_word => true) # silently fails if invalid
      end
    end
    
    self.where(:stop_word => true).count
  end
  
  ##
  # Creates search index word records from collection metadata
  #
  # Contribution-specific metadata fields:
  # * Title
  # * Alternative title
  # * Protagonist names
  # * Contributor name
  # * Contributed on behalf of
  # * Creator name
  # * Subject 
  # * Location name
  #
  # Taxonomy terms:
  # * Keywords
  # * Keywords: Forces
  # * Theatres of War
  # * File type
  #
  # @todo Fix consecutive runs of this getting different numbers of phrases.
  #
  def self.from_collection_metadata!
    # Hash of frequencies keyed by phrase
    phrase_freqs = { }
    
    # Searchable taxonomy terms
    MetadataField.includes(:taxonomy_terms).where(:field_type => 'taxonomy', :searchable => true).each do |field|
      field.taxonomy_terms.each do |tt|
        term = tt.term.downcase.strip
        if term.match(/\s/) || self.where(:text => term).first.blank?
          freq = Contribution.select('id').where(:id => tt.metadata_record_ids).size
          phrase_freqs[term] = freq
        end
      end
    end
    
    # Contribution-specific metadata
    includes = [ 
      { :metadata => :taxonomy_terms }, 
      { :contributor => :contact }
    ]
    Contribution.published.includes(includes).find_each do |contribution|
      phrases = [ ]
      phrases << contribution.title
      phrases << contribution.metadata.fields['alternative']
      phrases << Contact.full_name(contribution.metadata.fields['character1_given_name'], contribution.metadata.fields['character1_family_name'])
      phrases << Contact.full_name(contribution.metadata.fields['character2_given_name'], contribution.metadata.fields['character2_family_name'])
      phrases << contribution.contact.full_name
      phrases << contribution.metadata.fields['contributor_behalf']
      phrases << Contact.full_name(contribution.metadata.fields['creator_given_name'], contribution.metadata.fields['creator_family_name'])
      phrases << contribution.metadata.fields['subject']
      phrases << contribution.metadata.fields['location_placename']
      
      # Only *phrases*, i.e. with a space
      phrases.reject! { |phrase| phrase.blank? || !phrase.strip.match(/\s/) }
      
      phrases.each do |phrase|
        key = phrase.downcase.strip
        if phrase_freqs.has_key?(key)
          phrase_freqs[key] = phrase_freqs[key] + 1
        else
          phrase_freqs[key] = 1
        end
      end
    end
    
    # Get rid of those that will fail validation.
    # (Much faster than going to ActiveModel::Validations)
    phrase_freqs.reject! do |phrase, freq|
      (phrase.length < self.min_word_length) || (freq < self.min_frequency) || phrase.match(/^\d+$/)
    end
    
    lower_phrases = phrase_freqs.keys
    existing_phrase_freqs = {}
    
    self.where(:stop_word => false).find_each do |phrase|
      if lower_phrases.include?(phrase.text)
        existing_phrase_freqs[phrase.text] = phrase.frequency
      else
        phrase.destroy 
      end
    end
    
    phrase_freqs.each_pair do |phrase, freq|
      if existing_phrase_freqs.has_key?(phrase)
        unless existing_phrase_freqs[phrase] == freq
          self.update_all({ :frequency => freq }, { :stop_word => false, :text => phrase })
        end
      else
        self.create(:text => phrase, :frequency => freq, :stop_word => false) # silently fails if invalid
      end
    end
    
    self.where(:stop_word => false).count
  end
  
  ##
  # ThinkingSphinx index block
  #
  # [Commented out as ActiveRecord query used for searches against this table.]
  #define_index do
  #  indexes text
  #  has frequency
  #  set_property :enable_star => 0
  #  set_property :min_prefix_len => self.min_prefix_length
  #  set_property :max_matches => self.max_matches
  #end
end
