require 'yaml'
require 'cgi'
require 'time'
require 'rubygems'
require 'nokogiri'
require 'active_support'

#OPTIMIZE use options hashes for improved readability

module Thimblr
  class ParserNew
    BackCompatibility = {"Type" => { "Regular"      => "Text",
                                     "Conversation" => "Chat" }
    }
                        
    Defaults = {
      'PostsPerPage'       => 10,
      'AskLabel'           => "Ask me anything",
      'SubmissionsEnabled' => true,
      'TwitterUsername'    => "tumblr",
      'RSS'                => '/rss',
      'CopyrightYears'     => '2009 - ' + Date.today.year.to_s,
      'Favicon'            => 'http://assets.tumblr.com/images/default_avatar_16.gif',
      'PortraitURL-16'     => "http://30.media.tumblr.com/avatar_013241641371_16.png",
      'PortraitURL-24'     => "http://30.media.tumblr.com/avatar_013241641371_24.png",
      'PortraitURL-30'     => "http://30.media.tumblr.com/avatar_013241641371_30.png",
      'PortraitURL-40'     => "http://30.media.tumblr.com/avatar_013241641371_40.png",
      'PortraitURL-48'     => "http://30.media.tumblr.com/avatar_013241641371_48.png",
      'PortraitURL-64'     => "http://30.media.tumblr.com/avatar_013241641371_64.png",
      'PortraitURL-96'     => "http://30.media.tumblr.com/avatar_013241641371_96.png",
      'PortraitURL-128'    => "http://30.media.tumblr.com/avatar_013241641371_128.png"
    }
    
    PostTypes = ["Text", "Photo", "Photoset", "Quote", "Link", "Chat", "Audio", "Video", "Answer"]
    
    # loads default data, no matter what the sample data is.
    # this gives data from imported blogs some more stuff, since an un-authenticated API call doesn't reveal all data
    def load_default_data
      @following    = YAML::load(open("config/following.yml"))
      @followed     = YAML::load(open("config/followed.yml"))
      @groupmembers = YAML::load(open("config/groupmembers.yml"))
    end
    
    def initialize(theme_code, blog_name = "demo")
      @blog = ImportedBlog.find_by_name(blog_name, :include => [:posts, :pages])
      template = YAML::load(open("config/demo.yml"))
      
      load_default_data
      
      @theme = theme_code
    end
    
    def render_index
      parse_meta_options
      
      render_block("IndexPage")
      render_block("More")
      
      
      render_posts unless @blog.posts.blank?
      
      
      #pagination
      replace_variable("CurrentPage", "1")
      replace_variable("NextPage", "/page/2")
      replace_variable("TotalPages", "100")
      
      render_block("Pagination")
      render_block("NextPage")
      strip_block("PreviousPage")
      
      render_following unless @following.blank?
      
      replace_variable "CopyrightYears", Defaults['CopyrightYears']
      replace_variable "RSS", Defaults['RSS']
      replace_variable "Favicon", Defaults['Favicon']
      replace_variable "PortraitURL-16", Defaults['PortraitURL-16']
      replace_variable "PortraitURL-24", Defaults['PortraitURL-24']
      replace_variable "PortraitURL-30", Defaults['PortraitURL-30']
      replace_variable "PortraitURL-40", Defaults['PortraitURL-40']
      replace_variable "PortraitURL-48", Defaults['PortraitURL-48']
      replace_variable "PortraitURL-64", Defaults['PortraitURL-64']
      replace_variable "PortraitURL-96", Defaults['PortraitURL-96']
      replace_variable "PortraitURL-128", Defaults['PortraitURL-128']
      
      disable_unsupported_stuff

      return @theme
    end
    
    
    def render_posts
      posts_template = fetch_content_of_block "Posts"
    
      #stores all rendered posts, concatenated together
      all_rendered_posts = String.new
      template = String.new
      
      @blog.posts.each do |post|
        template = posts_template.dup
        
        case post.post_type
        when 'Regular', 'Text'
          
          only_render_block_for_post_type("Text", template)
          
          if post.content[:'regular-title'].nil?
            strip_block "Title", template
          else
            render_block "Title", nil, template
            replace_variable "Title", post.content[:'regular-title'], template
          end
          
          replace_variable "Body", post.content[:'regular-body'], template
          
        when 'Photo'
          
          only_render_block_for_post_type("Photo", template)
          
          replace_variable "PhotoURL-500", post.content[:photo_url_500], template
          replace_variable "PhotoURL-400", post.content[:photo_url_400], template
          replace_variable "PhotoURL-250", post.content[:photo_url_250], template
          replace_variable "PhotoURL-100", post.content[:photo_url_100], template
          replace_variable "PhotoURL-75sq", post.content[:photo_url_75], template
          replace_variable "PhotoURL-HighRes", post.content[:photo_url_1280], template
          
          if post.content[:'photo-link-url'].nil?
            replace_variable "LinkOpenTag", '', template
            replace_variable "LinkCloseTag", '', template
            replace_variable "LinkURL", '', template
          else
            replace_variable "LinkOpenTag", "<a href='post.content[:'photo-link-url']'>", template
            replace_variable "LinkCloseTag", '</a>', template
            replace_variable "LinkURL", post.content[:'photo-link-url'], template
          end
          
          if post.content[:'photo-caption'].nil?
            strip_block "Caption", template
            replace_variable "PhotoAlt", '', template
          else
            render_block "Caption", nil, template
            replace_variable "Caption", post.content[:'photo-caption'], template
            # OPTIMIZE wrap regex in meaningful method name!?
            replace_variable "PhotoAlt", post.content[:'photo-caption'].gsub(/\<\/?[^\>]*\>/, ""), template
          end
          
          if post.content[:photo_url_1280].present? and post.content[:photo_url_1280] != post.content[:photo_url_500]
            render_block "HighRes", nil, template
          else
            strip_block "HighRes", template
          end
          
        when 'Quote'
          
          only_render_block_for_post_type("Quote", template)
          
          replace_variable "Quote", post.content[:"quote-text"], template
          replace_variable "Length", "medium", template # TODO use 'real' values
          
          if post.content[:'quote-source'].present?
            render_block "Source", nil, template
            replace_variable "Source", post.content[:'quote-source'], template
          else
            strip_block "Source", template
          end
          
        end # of case
        
        # stuff for all post types
        replace_variable "Permalink", post.url_with_slug, template
        replace_variable "ShortURL", "http://tumblr.com/xpv5qtavm", template
        replace_variable "PostID", post.postid, template
        
        # Dates http://www.tumblr.com/docs/en/custom_themes#dates
        render_block "Date", nil, template
        replace_variable "DayOfMonth", post.date.day.to_s, template
        replace_variable "DayOfMonthWithZero", post.date.strftime("%d"), template
        replace_variable "DayOfWeek", post.date.strftime("%A"), template
        replace_variable "ShortDayOfWeek", post.date.strftime("%a"), template
        replace_variable "DayOfWeekNumber", (post.date.strftime("%w").to_i + 1).to_s, template
        replace_variable "DayOfMonthSuffix", "th", template #FIXME fix day suffix
        replace_variable "DayOfYear", post.date.strftime("%j"), template
        replace_variable "WeekOfYear", post.date.strftime("%W"), template
        replace_variable "Month", post.date.strftime("%B"), template
        replace_variable "ShortMonth", post.date.strftime("%b"), template
        replace_variable "MonthNumber", post.date.month.to_s, template
        replace_variable "MonthNumberWithZero", post.date.strftime("%w"), template
        replace_variable "Year", post.date.strftime("%w"), template
        replace_variable "ShortYear", post.date.strftime("%y"), template
        replace_variable "CapitalAmPm", post.date.strftime("%p"), template
        replace_variable "AmPm", post.date.strftime("%p").downcase, template
        replace_variable "12Hour", post.date.strftime("%I").sub(/^0/,""), template
        replace_variable "24Hour", post.date.hour.to_s, template
        replace_variable "12HourWithZero", post.date.strftime("%I"), template
        replace_variable "24HourWithZero", post.date.strftime("%H"), template
        replace_variable "Minutes", post.date.strftime("%M"), template
        replace_variable "Seconds", post.date.strftime("%S"), template
        replace_variable "Beats", ((post.date.usec / 1000).round).to_s, template
        replace_variable "TimeAgo", "Some time ago", template
        replace_variable "Timestamp", post.unix_timestamp, template
        
        all_rendered_posts += template
      end
      
      render_block "Posts", all_rendered_posts
      
    end
    
    
    # pass in a post_type and the posts template ({block:Posts})
    # will render the block of the post_type and remove all others
    def only_render_block_for_post_type(post_type, posts_template)
      types_to_remove = PostTypes.reject { |type| type == post_type }
      
      types_to_remove.each { |type| strip_block(type, posts_template) }
      
      render_block post_type, nil, posts_template
    end
    
    
    
    # stuff that is currently unsupported by thimblr
    # This also serves as a TODO list
    def disable_unsupported_stuff
      strip_block "Likes"
      strip_block "SearchPage"
      replace_variable "SearchQuery", ""
      replace_variable "URLSafeSearchQuery", ""
      replace_variable "SearchResultCount", ""
      strip_block "NoSearchResults"
      strip_block "Twitter"
      strip_block "TagPage"
      strip_block "DayPage"
      strip_block "DayPagination"
      strip_block "PreviousDayPage"
      strip_block "NextDayPage"
      strip_block "PostNotes"
      strip_block "NoteCount"
      strip_block "GroupMembers"
      strip_block "GroupMember"
    end
    
    # renders blocks 'Following' and 'Followed'
    # How it works:
    # 1. Fetch contents of the block 'Followed' and store it as a template for each followed blog
    # 2. For each followed blog, replace the variables of the template with the appropriate replacement
    # 3. Concatenate the rendered code of each followed blog into a string
    # 4. Render block 'Followed' and replace original contents with the concatenated string
    # 5. Render block 'Following' 
    def render_following
      following_template = fetch_content_of_block("Followed")
      
      # stores the concatenated result of all the rendered following_templates
      rendered_followed = String.new
      
      @following.each do |blog|
        rendered_template = following_template.dup
        rendered_template.sub!(/\{FollowedName\}/i, blog['Name'])
        rendered_template.sub!(/\{FollowedTitle\}/i, blog['Title'])
        rendered_template.sub!(/\{FollowedURL\}/i, blog['URL'])
        rendered_template.sub!(/\{FollowedPortraitURL-16\}/i, blog['PortraitURL-16'])
        rendered_template.sub!(/\{FollowedPortraitURL-24\}/i, blog['PortraitURL-24'])
        rendered_template.sub!(/\{FollowedPortraitURL-30\}/i, blog['PortraitURL-30'])
        rendered_template.sub!(/\{FollowedPortraitURL-40\}/i, blog['PortraitURL-40'])
        rendered_template.sub!(/\{FollowedPortraitURL-48\}/i, blog['PortraitURL-48'])
        rendered_template.sub!(/\{FollowedPortraitURL-64\}/i, blog['PortraitURL-64'])
        rendered_template.sub!(/\{FollowedPortraitURL-96\}/i, blog['PortraitURL-96'])
        rendered_template.sub!(/\{FollowedPortraitURL-128\}/i, blog['PortraitURL-128'])
        
        rendered_followed += rendered_template
      end
      
      render_block("Followed", rendered_followed)
      render_block("Following")
    end
    
    # returns the contents of the provided block
    def fetch_content_of_block(block_name)
      @theme.match(block_regex_pattern_for(block_name))
      block_content = $2 #@theme.match(block_regex_pattern_for(block_name))[2]
    end
    
    # Scans the whole theme and replaces a variable with the replacement provided
    def replace_variable(var_name, replacement, string = @theme)
      print "Replacing variable {#{var_name}}..."
      if string.gsub!(/\{#{var_name}\}/i, replacement)
        puts "with '#{replacement}'"
      else
        puts "no match found!"
      end
      
      #TODO handle variable transformations
    end
    
    # The regular expression to match a block and its contents
    # matchdata $2 will be the content of the block
    def block_regex_pattern_for(block_name)  
      Regexp.new(/\{block:(#{block_name})\}((.|\s)*?)\{\/block:(#{block_name})\}/)
    end
    
    # looks for the block named 'block_name'
    # and replaces the whole block with just the content of the block or a provided replacement for this content
    def render_block(block_name, replacement = nil, string = @theme)
      print "Rendering block {block:#{block_name}}..."
      if string.gsub!(block_regex_pattern_for(block_name)) { |match| replacement || $2 }
        puts "found and replaced!"
      else
        puts "no match found!"
      end
    end
    
    # removes a whole block
    def strip_block(block_name, string = @theme)
      print "Stripping block {block:#{block_name}}..."
      if string.gsub!(block_regex_pattern_for(block_name), '')
        puts "removed!"
      else
        puts "no match found!"
      end
    end
    
    # handles <meta> tags Appearance Options
    # OPTIMIZE check whether in some cases sub is sufficient (instead of gsub)
    # OPTIMIZE maybe put every option type (color, font, boolean etc.) in a separate method
    def parse_meta_options
      doc = Nokogiri::HTML.parse(@theme)
      meta_elements = doc.search('meta')
      
      meta_elements.each do |element|
        break if element['name'].blank?
        
        # handling custom colors and fonts: http://www.tumblr.com/docs/en/custom_themes#appearance-options
        if element['name'].present? and element['content'].present? and (element['name'].include? 'color' or element['name'].include? 'font')
          replace_variable(element['name'], element['content'])
        end
        
        # Handling Booleans: http://www.tumblr.com/docs/en/custom_themes#booleans
        if element['name'].include? 'if:'
          if element['content'] == "1"
            # converts something like "if:Show People I Follow" to "IfShowPeopleIFollow"
            render_block(element['name'].titlecase.gsub(/\W/, ''))
            # converts something like "if:Show People I Follow" to "IfNotShowPeopleIFollow"
            strip_block(element['name'].titlecase.gsub(':', 'Not').gsub(/\W/, ''))
          else
            strip_block(element['name'].titlecase.gsub(/\W/, ''))
            render_block(element['name'].titlecase.gsub(':', 'Not').gsub(/\W/, ''))
          end
        end
        
        # Handling custom text: http://www.tumblr.com/docs/en/custom_themes#custom-text
        if element['name'].include? 'text:'
          if element['content'].present?
            replace_variable(element['name'], element['content'])
            # converts something like "text:Flickr Username" to "IfFlickrUsername"
            render_block(element['name'].gsub('text', 'if').titlecase.gsub(/\W/, ''))
          else
            strip_block(element['name'].gsub('text', 'if').titlecase.gsub(/\W/, ''))
          end
        end
        
        # Handling custom images: http://www.tumblr.com/docs/en/custom_themes#custom-images
        if element['name'].include? 'image:'
          if element['content'].present?
            replace_variable(element['name'], element['content'])
            # converts something like "image:Header" Username" to "IfHeaderImage"
            render_block(element['name'].gsub('image', 'if').titlecase.gsub(/\W/, '') + "Image")
            # converts something like "image:Header" Username" to "IfNotHeaderImage"
            strip_block(element['name'].gsub('image', 'if').titlecase.gsub(':', 'Not').gsub(/\W/, '') + "Image")
          else
            strip_block(element['name'].gsub('image', 'if').titlecase.gsub(/\W/, '') + "Image")
            render_block(element['name'].gsub('image', 'if').titlecase.gsub(':', 'Not').gsub(/\W/, '') + "Image")
          end
        end
      end # of meta_elements each
      
      # Removing {CustomCSS}
      replace_variable("CustomCSS", '')
    end # of method generate_meta
    
  end # of class
end # of module