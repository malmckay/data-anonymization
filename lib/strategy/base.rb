module DataAnon
  module Strategy
    class Base
      include Utils::Logging

      attr_accessor :fields, :user_strategies, :fields_missing_strategy, :errors

      def initialize source_database, destination_database, name, user_strategies
        @name = name
        @user_strategies = user_strategies
        @fields = {}
        @source_database = source_database
        @destination_database = destination_database
        @fields_missing_strategy = DataAnon::Core::FieldsMissingStrategy.new name
        @errors = DataAnon::Core::TableErrors.new(@name)
      end

      def self.whitelist?
        false
      end

      def process_fields &block
        self.instance_eval &block
        self
      end

      def primary_key *fields
        @primary_keys = fields
      end

      def whitelist *fields
        fields.each { |f| @fields[f.downcase] = DataAnon::Strategy::Field::Whitelist.new }
      end

      def anonymize *fields, &block
        if block.nil?
          fields.each { |f| @fields[f.downcase] = DataAnon::Strategy::Field::DefaultAnon.new(@user_strategies) }
          temp = self
          return Class.new do
            @temp_fields = fields
            @table_fields = temp.fields
            def self.using field_strategy
              @temp_fields.each { |f| @table_fields[f.downcase] = field_strategy }
            end
          end
        else
          fields.each { |f| @fields[f.downcase] = DataAnon::Strategy::Field::Anonymous.new(&block) }
        end
      end

      def is_primary_key? field
        @primary_keys.select { |key| field.downcase == key.downcase }.length > 0
      end

      def default_strategy field_name
        @fields_missing_strategy.missing field_name
        DataAnon::Strategy::Field::DefaultAnon.new(@user_strategies)
      end

      def dest_table
        return @dest_table unless @dest_table.nil?
        DataAnon::Utils::DestinationDatabase.establish_connection @destination_database if @destination_database
        @dest_table = Utils::DestinationTable.create @name, @primary_keys
      end

      def source_table
        return @source_table unless @source_table.nil?
        DataAnon::Utils::SourceDatabase.establish_connection @source_database
        @source_table = Utils::SourceTable.create @name, @primary_keys
      end

      def process
        logger.debug "Processing table #{@name} with fields strategies #{@fields}"
        total = source_table.count
        if total > 0
          index = 0
          progress = progress_bar.new(@name, total)
          source_table.all.each do |record|
            index += 1
            begin
              process_record index, record
            rescue => exception
              @errors.log_error record, exception
            end
            progress.show index
          end
          progress.close
        end
      end

      def progress_bar
        @progress_bar || DataAnon::Utils::ProgressBar
      end

      def progress_bar_class progress_bar
        @progress_bar = progress_bar
      end


    end
  end
end