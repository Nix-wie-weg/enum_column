# This module provides all the column helper methods to deal with the
# values and adds the common type management code for the adapters.

adapter_class =
  if defined? ActiveRecord::ConnectionAdapters::Mysql2Adapter
    ActiveRecord::ConnectionAdapters::Mysql2Adapter
  elsif defined? ActiveRecord::ConnectionAdapters::MysqlAdapter
    ActiveRecord::ConnectionAdapters::MysqlAdapter
  end

if adapter_class
  adapter_class.class_eval do
    protected
    if instance_methods.include?(:initialize_type_map)
      def initialize_type_map_with_enum_types(m)
        initialize_type_map_without_enum_types(m)
        m.register_type(/enum/i) do |sql_type|
          limit = sql_type
            .sub(/^enum\('(.+)'\)/i, '\1')
            .split("','")
            .map(&:intern)
          ActiveRecord::Type::Enum.new(limit: limit)
        end
      end
      alias_method_chain :initialize_type_map, :enum_types
    end
  end
end

# Try Rails 3.1, then Rails 3.2+, then mysql column adapters
column_class =
  if defined? ActiveRecord::ConnectionAdapters::Mysql2Column
    ActiveRecord::ConnectionAdapters::Mysql2Column
  elsif defined? ActiveRecord::ConnectionAdapters::MysqlColumn
    ActiveRecord::ConnectionAdapters::MysqlColumn
  elsif defined? ActiveRecord::ConnectionAdapters::Mysql2Adapter::Column
    ActiveRecord::ConnectionAdapters::Mysql2Adapter::Column
  elsif defined? ActiveRecord::ConnectionAdapters::MysqlAdapter::Column
    ActiveRecord::ConnectionAdapters::MysqlAdapter::Column
  else
    ObviousHint::NoMysqlAdapterFound
  end

column_class.module_eval do
  alias_method :__klass_enum, :klass

  # The class for enum is Symbol.
  def klass
    if type == :enum
      Symbol
    else
      __klass_enum
    end
  end

  if instance_methods.include?(:extract_default)
    alias_method :__extract_default_enum, :extract_default

    def extract_default
      @default = @default.intern if type == :enum && @default.present?
      __extract_default_enum
    end
  end

  def __enum_type_cast(value)
    if type == :enum
      self.class.value_to_symbol(value)
    else
      __type_cast_enum(value)
    end
  end

  if instance_methods.include?(:type_cast_from_database)
    alias_method :__type_cast_enum, :type_cast_from_database

    # Convert to a symbol.
    def type_cast_from_database(value)
      __enum_type_cast(value)
    end
  elsif instance_methods.include?(:type_cast)
    alias_method :__type_cast_enum, :type_cast

    def type_cast(value)
      __enum_type_cast(value)
    end
  end

  # Deprecated in Rails 4.1
  if instance_methods.include?(:type_cast_code)
    alias_method :__type_cast_code_enum, :type_cast_code

    # Code to convert to a symbol.
    def type_cast_code(var_name)
      if type == :enum
        "#{self.class.name}.value_to_symbol(#{var_name})"
      else
        __type_cast_code_enum(var_name)
      end
    end
  end

  class << self
    # Safely convert the value to a symbol.
    def value_to_symbol(value)
      case value
      when Symbol
        value
      when String
        value.empty? ? nil : value.intern
      end
    end
  end

  private

  # Deprecated in Rails 4.2
  if private_instance_methods.include?(:simplified_type)
    alias_method :__simplified_type_enum, :simplified_type

    # The enum simple type.
    def simplified_type(field_type)
      if field_type =~ /enum/i
        :enum
      else
        __simplified_type_enum(field_type)
      end
    end
  end

  # Deprecated in Rails 4.2
  if private_instance_methods.include?(:extract_limit)
    alias_method :__extract_limit_enum, :extract_limit

    def extract_limit(sql_type)
      if sql_type =~ /^enum/i
        sql_type.sub(/^enum\('(.+)'\)/i, '\1').split("','").map(&:intern)
      else
        __extract_limit_enum(sql_type)
      end
    end
  end
end

# Rails 4.2 type annotations
if defined? ActiveRecord::Type::Value
  module ActiveRecord
    module Type
      class Enum < Value # :nodoc:
        def type
          :enum
        end

        def type_cast_for_database(value)
          value.to_s if value.present?
        end

        private

        def cast_value(value)
          value.to_sym if value.present?
        end
      end
    end
  end
end
