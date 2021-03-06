module Presenting
  class Search
    include Presenting::Configurable

    # I want to support three configuration formats:
    #
    #   Search.new(:fields => [:first_name, :last_name, :email])
    #
    #   Search.new(:fields => {
    #    'first_name' => :equals,
    #    'last_name' => :begins_with,
    #    'email' => :not_null
    #   })
    #
    #   Search.new(:fields => {
    #    'fname' => {:sql => 'first_name', :pattern => :equals},
    #    'lname' => {:sql => 'last_name', :pattern => :begins_with},
    #    'email' => {:sql => 'email', :pattern => :not_null}
    #   })
    def fields=(obj)
      case obj
      when Array
        obj.each do |name| fields << name end
        
      when Hash
        obj.each do |k, v|
          fields << {k => v}
        end 
      end
    end
    
    def fields
      @fields ||= FieldSet.new
    end
    
    def to_sql(params, type = :simple)
      send("to_#{type}_sql", params) unless params.blank?
    end
    
    protected
    
    # handles a simple search where a given term is matched against a number of fields, and can match any of them.
    # this is usually presented to the user as a single "smart" search box.
    def to_simple_sql(term)
      sql = fields.map(&:fragment).join(' OR ')
      binds = fields.collect{|f| f.bind(term)}.compact
      [sql, binds].flatten.compact
    end
    
    # handles a search setup where a user may enter a search value for any field, and anything entered must match.
    # this is usually presented to the user as a set of labeled search boxes.
    #
    # example field terms:
    #   field_terms = {
    #     'first_name' => {:value => 'Bob'}
    #     'last_name' => {:value => 'Smith'}
    #   }
    #
    def to_field_sql(field_terms)
      searched_fields = fields.select{|f| field_terms[f.name] and not field_terms[f.name][:value].blank?}
      unless searched_fields.empty?
        sql = searched_fields.map(&:fragment).join(' AND ')
        binds = searched_fields.collect{|f| f.bind(field_terms[f.name][:value])}

        [sql, binds].flatten.compact
      end
    end
    
    class FieldSet < Array
      def <<(val)
        if val.is_a? Hash
          k, v = *val.to_a.first
          opts = v.is_a?(Hash) ? v : {:pattern => v}
          opts[:name] = k
        else
          opts = {:name => val}
        end
        super Field.new(opts)
      end
    end
    
    # TODO: a field may require extra joins when it is searched on
    # TODO: support more than just mysql (need access to a Connection for quoting and attribute conditions)
    class Field
      include Presenting::Configurable
      
      # required (this is what appears in the parameter hash)
      attr_reader :name
      def name=(val)
        @name = val.to_s
      end
      
      # sql field (default == name)
      def sql
        @sql ||= name
      end
      attr_writer :sql
      
      # a shortcut for common operator/bind_pattern combos
      def pattern=(val)
        case val
        when :equals
          self.operator = '= ?'
          self.bind_pattern = '?'
        when :begins_with
          self.operator = 'LIKE ?'
          self.bind_pattern = '?%'
        when :ends_with
          self.operator = 'LIKE ?'
          self.bind_pattern = '%?'
        when :contains
          self.operator = 'LIKE ?'
          self.bind_pattern = '%?%'
        when :null
          self.operator = 'IS NULL'
        when :not_null
          self.operator = 'IS NOT NULL'
        when :true
          self.operator = '= ?'
          self.bind_pattern = true
        when :false
          self.operator = '= ?'
          self.bind_pattern = false
        when :less_than
          self.operator = '< ?'
        when :less_than_or_equal_to, :not_greater_than
          self.operator = '<= ?'
        when :greater_than
          self.operator = '> ?'
        when :greater_than_or_equal_to, :not_less_than
          self.operator = '>= ?'
        end
      end
      
      # the format for comparison with :sql, with an optional bind for search terms
      # '= ?', 'LIKE ?', 'IN (?)', etc.
      def operator
        @operator ||= '= ?'
      end
      attr_writer :operator
      
      # formats the term BEFORE binding into the sql
      # e.g. '?', '?%', etc.
      def bind_pattern
        @bind_pattern ||= '?'
      end
      attr_writer :bind_pattern
      
      # composes the sql fragment
      def fragment
        "#{sql} #{operator}"
      end
      
      # prepares the bindable term
      def bind(term)
        return nil unless operator.include?('?')
        return bind_pattern unless bind_pattern.is_a? String
        bind_pattern == '?' ? typecast(term) : bind_pattern.sub('?', typecast(term).to_s)
      end
      
      # you can set a data type for the field, which will be used to convert
      # parameter values. currently this is mostly useful for :time searches.
      attr_accessor :type
      
      protected
      
      def typecast(val)
        case type
        when :date
          val.is_a?(String) ?
            (Time.zone ? Time.zone.parse(val) : Time.parse(val)).to_date :
            val
          
        when :time, :datetime
          val.is_a?(String) ?
            (Time.zone ? Time.zone.parse(val) : Time.parse(val)) :
            val

        else
          val.to_s.strip
        end
      end
    end
  end
end
