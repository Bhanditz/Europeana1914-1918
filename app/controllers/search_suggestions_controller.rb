class SearchSuggestionsController < ApplicationController
  def query
    query = params[:q]
    
    # Do not make suggestions beneath a minimum length
    words = if query.blank? || query.length < SearchSuggestion.min_word_length
      []
    else
      # This would query using Sphinx
      #results = SearchSuggestion.search(query, :match_mode => :phrase, :order => :frequency, :sort_mode => :desc)
      
      # This queries using ActiveRecord
      results = SearchSuggestion.where("text LIKE '#{query}%'").order('frequency DESC').limit(SearchSuggestion.max_matches)
      
      results.reject { |word| word.blank? }.collect { |word| word.text }
    end
    
    respond_to do |format|
      format.json { render :json => words }
    end
  end
end
