require "digest/md5"
require "socket"

module Moped
  module BSON
    class ObjectId
      include Comparable

      # Serialize the object id to its raw bytes.
      #
      # @example Serialize the object id.
      #   object_id.__bson_dump__("", "_id")
      #
      # @param [ String ] io The raw bytes to write to.
      # @param [ String ] key The field name.
      #
      # @since 1.0.0
      def __bson_dump__(io, key)
        io << Types::OBJECT_ID
        io << key.to_bson_cstring
        io << data
      end

      # Check equality on the object.
      #
      # @example Check equality.
      #   object === other
      #
      # @param [ Object ] other The object to check against.
      #
      # @return [ true, false ] If the objects are equal.
      #
      # @since 1.0.0
      def ===(other)
        return to_str === other.to_str if other.respond_to?(:to_str)
        super
      end

      # Check equality on the object.
      #
      # @example Check equality.
      #   object == other
      #
      # @param [ Object ] other The object to check against.
      #
      # @return [ true, false ] If the objects are equal.
      #
      # @since 1.0.0
      def ==(other)
        BSON::ObjectId === other && data == other.data
      end
      alias :eql? :==

      # Compare this object with another object, used in sorting.
      #
      # @example Compare the two objects.
      #   object <=> other
      #
      # @param [ Object ] other The object to compare to.
      #
      # @return [ Integer ] The result of the comparison.
      #
      # @since 1.0.0
      def <=>(other)
        data <=> other.data
      end

      # Get the raw data (bytes) for the object id.
      #
      # @example Get the raw data.
      #   object_id.data
      #
      # @return [ String ] The raw bytes.
      #
      # @since 1.0.0
      def data
        # If @data is defined, then we know we've been loaded in some
        # non-standard way, so we attempt to repair the data.
        repair! @data if defined? @data
        @raw_data ||= @@generator.next
      end

      # Return the UTC time at which this ObjectId was generated. This may
      # be used instread of a created_at timestamp since this information
      # is always encoded in the object id.
      #
      # @example Get the generation time.
      #   object_id.generation_time
      #
      # @return [ Time ] The time the id was generated.
      #
      # @since 1.0.0
      def generation_time
        Time.at(data.unpack("N")[0]).utc
      end

      # Gets the hash code for the object.
      #
      # @example Get the hash code.
      #   object.hash
      #
      # @return [ Fixnum ] The hash code.
      #
      # @since 1.0.0
      def hash
        data.hash
      end

      # Gets the string inspection for the object.
      #
      # @example Get the string inspection.
      #   object.inspect
      #
      # @return [ String ] The inspection.
      #
      # @since 1.0.0
      def inspect
        to_s.inspect
      end

      # Dump the object for use in a marshal dump.
      #
      # @example Dump the object.
      #   object.marshal_dump
      #
      # @return [ String ] The dumped object.
      #
      # @since 1.0.0
      def marshal_dump
        data
      end

      # Load the object from the marshal dump.
      #
      # @example Load the object.
      #   object.marshal_load("")
      #
      # @param [ String ] data The raw data.
      #
      # @since 1.0.0
      def marshal_load(data)
        self.data = data
      end

      # Convert the object to a JSON string.
      #
      # @example Convert to a JSON string.
      #   obejct.to_json
      #
      # @return [ String ] The object as JSON.
      #
      # @since 1.0.0
      def to_json(*args)
        "{\"$oid\": \"#{to_s}\"}"
      end

      # Get the string representation of the object.
      #
      # @example Get the string representation.
      #   object.to_s
      #
      # @return [ String ] The string representation.
      #
      # @since 1.0.0
      def to_s
        data.unpack("H*")[0].force_encoding(Moped::BSON::UTF8_ENCODING)
      end
      alias :to_str :to_s

      private

      # Private interface for setting the internal data for an object id.
      def data=(data)
        @raw_data = data
      end

      # Attempts to repair ObjectId data marshalled in previous formats.
      #
      # The first check covers an ObjectId generated by the mongo-ruby-driver.
      #
      # The second check covers an ObjectId generated by moped before a custom
      # marshal strategy was added.
      def repair!(data)
        if data.is_a?(Array) && data.size == 12
          self.data = data.pack("C*")
        elsif data.is_a?(String) && data.size == 12
          self.data = data
        else
          raise TypeError, "Could not convert #{data.inspect} into an ObjectId"
        end
      end

      class << self

        def __bson_load__(io)
          from_data(io.read(12))
        end

        # Create a new object id from a string.
        #
        # @example Create an object id from the string.
        #   Moped::BSON::ObjectId.from_string(id)
        #
        # @param [ String ] string The string to create from.
        #
        # @return [ ObjectId ] The new object id.
        #
        # @since 1.0.0
        def from_string(string)
          raise Errors::InvalidObjectId.new(string) unless legal?(string)
          from_data [string].pack("H*")
        end

        # Create a new object id from a time.
        #
        # @example Create an object id from a time.
        #   Moped::BSON::ObjectId.from_id(time)
        #
        # @example Create an object id from a time, ensuring uniqueness.
        #   Moped::BSON::ObjectId.from_id(time, unique: true)
        #
        # @param [ Time ] time The time to generate from.
        # @param [ Hash ] options The options.
        #
        # @option options [ true, false ] :unique Whether the id should be
        #   unique.
        #
        # @return [ ObjectId ] The new object id.
        #
        # @since 1.0.0
        def from_time(time, options = nil)
          unique = (options || {})[:unique]
          from_data(unique ? @@generator.next(time.to_i) : [ time.to_i ].pack("Nx8"))
        end

        # Determine if the string is a legal object id.
        #
        # @example Is the string a legal object id?
        #   Moped::BSON::ObjectId.legal?(string)
        #
        # @param [ String ] The string to test.
        #
        # @return [ true, false ] If the string is legal.
        #
        # @since 1.0.0
        def legal?(string)
          /\A\h{24}\Z/ === string.to_s
        end

        # Create a new object id from some raw data.
        #
        # @example Create an object id from raw data.
        #   Moped::BSON::ObjectId.from_data(data)
        #
        # @param [ String ] data The raw bytes.
        #
        # @return [ ObjectId ] The new object id.
        #
        # @since 1.0.0
        def from_data(data)
          id = allocate
          id.send(:data=, data)
          id
        end
      end

      # @api private
      class Generator
        def initialize
          # Generate and cache 3 bytes of identifying information from the current
          # machine.
          @machine_id = Digest::MD5.digest(Socket.gethostname).unpack("N")[0]

          @mutex = Mutex.new
          @counter = 0
        end

        # Return object id data based on the current time, incrementing the
        # object id counter.
        def next(time = nil)
          @mutex.lock
          begin
            counter = @counter = (@counter + 1) % 0xFFFFFF
          ensure
            @mutex.unlock rescue nil
          end

          generate(time || Time.new.to_i, counter)
        end

        # Generate object id data for a given time using the provided +counter+.
        def generate(time, counter = 0)
          process_thread_id = RUBY_ENGINE == 'jruby' ? "#{Process.pid}#{Thread.current.object_id}".hash % 0xFFFF : Process.pid
          [time, @machine_id, process_thread_id, counter << 8].pack("N NX lXX NX")
        end
      end

      @@generator = Generator.new
    end
  end
end
