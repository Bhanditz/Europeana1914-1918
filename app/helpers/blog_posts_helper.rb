require 'feedzirra'
require 'hpricot'

module BlogPostsHelper
  ##
  # Restores locale to links with href starting "/", i.e. local absolute links
  #
  # @example
  #   relocale_link('<a href="/contributions>Contributions</a>')
  #     #=> '<a href="/en/contributions>Contributions</a>'
  #
  # @param [String] string Text potentially containing local absolute HTML links
  # @return [String] string with locale introduced into beginning of local
  #   absolute links
  #
  def relocale_link(string)
    string.gsub(/href=(["'])\//, "href=#{$1}/" + I18n.locale.to_s + '/')
  end
  
  ##
  # Removes Blogger elements from HTML
  # 
  # Elements removed:
  # * div.blogger-post-footer
  #
  # @param [String] html HTML to remove Blogger elements from
  # @return [String] HTML with Blogger elements removed
  #
  def deblogger(html)
    html.gsub(/<div class="blogger-post-footer">.*?<\/div>/, '')
  end
  
  ##
  # Retrieves entries from one of the project blogs
  #
  # @param [Hash,Array<Hash>] options Options; additional options will be passed 
  #   on to {#europeana_blog_posts} or #{gwa_blog_posts}. If an Array of Hashes
  #   is passed, results from each blog will be combined and sorted 
  #   chronologically.
  # @option options [String] :blog The blog to retrieve posts from. Known values
  #   are 'europeana' and 'gwa'. If no value is set, defaults to 'europeana'.
  #   Any other value will raise an exception.
  # @return Array<Feedzirra::Parser::AtomEntry> array of feed entries
  # @see #europeana_blog_posts
  # @see #gwa_blog_posts
  #
  def blog_posts(options = {})
    options = HashWithIndifferentAccess.new(options)
    if blogs = options.delete(:blogs)
      blog_post_sets = blogs.collect do |blog_options| 
        blog_posts(options.merge(blog_options).merge({ :offset => 1, :limit => 0 }))
      end
      posts = blog_post_sets.flatten.sort { |a, b| b.published <=> a.published }
      filter_blog_posts(posts, { :offset => options[:offset], :limit => options[:limit] })
    else
      blog = options.delete(:blog)
      case blog
      when 'europeana', nil
        posts = europeana_blog_posts(options)
      when 'gwa'
        posts = gwa_blog_posts(options)
      else
        raise Exception, "Unknown blog \"#{blog.to_s}\""
      end
    end
  end
  
  def blog_read_more_link(options = {})
    options = HashWithIndifferentAccess.new(options)
    options[:offset] = (options[:offset] || 1).to_i + options[:limit].to_i
    options[:read_more] ||= 'true'
    if blog_posts(options).present?
      link_path = options[:blogs] ? blogs_post_path(options) : blog_post_path(options)
      link_to(t('views.blog_posts.read_more'), link_path, :id => 'read-more')
    else
      ''
    end
  end
  
protected
  
  ##
  # Retrieves entries from the Europeana 1914-1918 blog via Atom feed
  #
  # An array of {Feedzirra::Parser::AtomEntry} objects is returned. The content
  # attribute of these objects is run through {Hpricot} so can be searched 
  # as an HTML document using its methods.
  #
  # @example Get the first paragraph in an entry
  #   (europeana_blog_posts.first.content/"//p").first
  #
  # @example Get all links in an entry
  #   (europeana_blog_posts.first.content/"//a")
  #
  # @param [Hash] options Options; additional options will be passed on to 
  #   {#filter_blog_posts}
  # @option options [String] :category The blog category, without the locale.
  #   If not specified, blog entries retrieved will not be filtered by category.
  # @option options [Integer] :expires_in Number of seconds to cache the blog
  #   feed; defaults to 60 minutes. Setting category and locale options results
  #   in independent retrieval and caching of the feed for those options.
  # @option options [String,Symbol] :locale The locale to retrieve blog entries 
  #   for. If none are found for this locale, those from the English blog will 
  #   be returned instead.
  # @return Array<Feedzirra::Parser::AtomEntry> array of feed entries
  # @see #filter_blog_posts
  # @see https://github.com/hpricot/hpricot
  #
  def europeana_blog_posts(options = {})
    default_locale = 'en'
    url = "http://europeana1914-1918.blogspot.com/feeds/posts/default"

    if options[:locale].blank?
      options[:locale] = I18n.locale
    end
    options[:locale] = options[:locale].to_s
    
    category = ''
    if options[:category]
      category = category + options[:category] + '-'
    end
    
    unless category.blank? && (options[:locale] == default_locale)
      category = category + options[:locale]
    end
    
    unless category.blank?
      url = url + "/-/" + category
    end
    
    logger.debug("Europeana blogspot URL: #{url}")
    
    key = controller.fragment_cache_key(url)
    if result = controller.cache_store.read(key)
      cached_feed = result
    end
   
    unless controller.fragment_exist?(url)
      feed = Feedzirra::Feed.fetch_and_parse(url,
        :on_success => lambda { |url, feed| cache_blog_feed(url, feed, options[:expires_in]) },
        :on_failure => lambda { |url, code, header, body| cache_blog_feed(url, cached_feed, 60) })
    end
    
    if !(feed.respond_to?(:entries) && feed.entries.present?) && controller.fragment_exist?(url)
      feed = YAML::load(controller.read_fragment(url))
    end
    
    if feed.respond_to?(:entries) && feed.entries.present?
      filter_blog_posts(feed.entries, options.merge(:hpricot => true))
    elsif options[:locale] == default_locale
      []
    else
      europeana_blog_posts(options.merge(:locale => default_locale))
    end
  end
  
  ##
  # Retrieves entries from the Great War Archive blog via Atom feed
  #
  # Unlike {#europeana_blog_posts}, this method does not run the entries'
  # content through Hpricot.
  #
  # @see #europeana_blog_posts
  #
  def gwa_blog_posts(options = {})
    default_locale = 'en'
    url = "http://thegreatwararchive.blogspot.com/feeds/posts/default"
    url = url + "/-/"

    if options[:locale].blank?
      options[:locale] = I18n.locale
    end
    options[:locale] = options[:locale].to_s
    
    if options[:category].blank? && (options[:locale] == 'de')
      options[:locale] = 'De'
    end
    url = url + options[:locale]
    
    if options[:category]
      url = url + '-' + options[:category]
    end
    
    logger.debug("GWA blogspot URL: #{url}")
    
    key = controller.fragment_cache_key(url)
    if result = controller.cache_store.read(key)
      cached_feed = result
    end
   
    unless controller.fragment_exist?(url)
      feed = Feedzirra::Feed.fetch_and_parse(url,
        :on_success => lambda { |url, feed| cache_blog_feed(url, feed, options[:expires_in]) },
        :on_failure => lambda { |url, code, header, body| cache_blog_feed(url, cached_feed, 60) })
    end
    
    if !(feed.respond_to?(:entries) && feed.entries.present?) && controller.fragment_exist?(url)
      feed = YAML::load(controller.read_fragment(url))
    end

    if feed.respond_to?(:entries) && feed.entries.present?
      filter_blog_posts(feed.entries, options.merge(:hpricot => false))
    elsif options[:locale] == default_locale
      []
    else
      gwa_blog_posts(options.merge(:locale => default_locale))
    end
  end
  
  ##
  # Filters and processes an array of blog posts
  # 
  # @param [Array<Feedzirra::Parser::AtomEntry>] posts Unfiltered array of posts
  # @param [Hash] options Options
  # @option options [Boolean] :deblogger If true, run entry content through
  #   {#deblogger}
  # @options options [Boolean] :hpricot If true, run entry content
  # @option options [Integer] :limit Only return max this number of posts;
  #   default is to return all
  # @option options [Integer] :offset (1) Return posts starting from this 
  #   offset. First post is number 1.
  # @option options [Boolean] :relocale If true, run entry content through
  #   {#relocale_link}
  # @return [Array<Feedzirra::Parser::AtomEntry>] Filtered array of posts
  # @see #deblogger
  # @see #relocale_link
  # @see https://github.com/hpricot/hpricot
  #
  def filter_blog_posts(posts, options = {})
    posts = posts.reject { |entry| entry.blank? }
    
    posts.each do |entry| 
      if options[:relocale]
        entry.content = relocale_link(entry.content)
      end
      if options[:deblogger]
        entry.content = deblogger(entry.content)
      end
      if options[:hpricot]
        entry.content = Hpricot(entry.content)
      end
    end

    first_post_index  = ((options[:offset] || 1).to_i - 1)
    last_post_index   = first_post_index + ((options[:limit] || 0).to_i - 1)
    
    posts = [ posts[first_post_index..last_post_index] ].flatten
    posts.reject { |post| post.blank? }
  end
  
private

  ##
  # Caches a blog feed
  #
  # @param [String] key Cache fragment key
  # @param feed Feed to cache, converted to YAML
  # @param [Integer] expires_in (60 minutes) Time in seconds to cache feed for.
  # 
  def cache_blog_feed(key, feed, expires_in = nil)
    expires_in ||= 60.minutes
    if feed.respond_to?(:entries) && feed.entries.present?
      controller.write_fragment(key, feed.to_yaml, :expires_in => expires_in)
    elsif !feed.respond_to?(:entries) && feed.present?
      controller.write_fragment(key, feed, :expires_in => expires_in)
    end
  end
end

