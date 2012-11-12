require "bunny/compatibility"

module Bunny
  class Queue

    include Bunny::Compatibility


    #
    # API
    #

    attr_reader :channel, :name, :options

    def initialize(channel_or_connection, name = AMQ::Protocol::EMPTY_STRING, opts = {})
      # old Bunny versions pass a connection here. In that case,
      # we just use default channel from it. MK.
      @channel          = channel_from(channel_or_connection)
      @name             = name
      @options          = self.class.add_default_options(name, opts)
      @consumers        = Hash.new

      @durable          = @options[:durable]
      @exclusive        = @options[:exclusive]
      @server_named     = @name.empty?
      @auto_delete      = @options[:auto_delete]
      @arguments        = @options[:arguments]

      @default_consumer = nil

      declare! unless opts[:no_declare]
    end

    # @return [Boolean] true if this queue was declared as durable (will survive broker restart).
    # @api public
    def durable?
      @durable
    end # durable?

    # @return [Boolean] true if this queue was declared as exclusive (limited to just one consumer)
    # @api public
    def exclusive?
      @exclusive
    end # exclusive?

    # @return [Boolean] true if this queue was declared as automatically deleted (deleted as soon as last consumer unbinds).
    # @api public
    def auto_delete?
      @auto_delete
    end # auto_delete?

    # @return [Boolean] true if this queue was declared as server named.
    # @api public
    def server_named?
      @server_named
    end # server_named?

    def arguments
      @arguments
    end


    def bind(exchange, opts = {})
      @channel.queue_bind(@name, exchange, opts)
    end

    def unbind(exchange, opts = {})
      @channel.queue_unbind(@name, exchange, opts)
    end


    def pop(opts = {:ack => true}, &block)
      response = @channel.basic_get(@name, opts)

      h = if response.is_a?(AMQ::Protocol::Basic::GetOk)
            header, content = self.receive_delivery

            envelope = {:delivery_tag => response.delivery_tag, :redelivered => response.redelivered, :exchange => response.exchange, :routing_key => response.routing_key, :message_count => response.message_count}

            Hash[:header           => header.decode_payload,
                 :payload          => content,
                 :delivery_details => envelope]
          else
            {:header => nil, :payload => :queue_empty, :delivery_details => nil}
          end

      block ? block.call(h) : h
    end

    def receive_delivery
      header   = @channel.read_next_frame
      content  = ''

      if header.body_size > 0
        loop do
          body_frame = @channel.read_next_frame
          content << body_frame.decode_payload

          break if content.bytesize >= header.body_size
        end
      end

      [header, content]
    end
    protected :receive_delivery


    # Deletes the queue
    # @api public
    def delete(opts = {})
      @channel.queue_delete(@name, opts)
    end

    def status
      queue_declare_ok = @channel.queue_declare(@name, @options.merge(:passive => true))
      {:message_count => queue_declare_ok.message_count,
        :consumer_count => queue_declare_ok.consumer_count}
    end

    def message_count
      s = self.status
      s[:message_count]
    end

    def consumer_count
      s = self.status
      s[:consumer_count]
    end



    #
    # Implementation
    #

    # @private
    def declare!
      queue_declare_ok = @channel.queue_declare(@name, @options)
      @name = queue_declare_ok.queue
    end

    protected

    # @private
    def self.add_default_options(name, opts, block)
      { :queue => name, :nowait => (block.nil? && !name.empty?) }.merge(opts)
    end

    # @private
    def self.add_default_options(name, opts)
      # :nowait is always false for Bunny
      h = { :queue => name, :nowait => false }.merge(opts)

      if name.empty?
        {
          :passive     => false,
          :durable     => false,
          :exclusive   => false,
          :auto_delete => false,
          :arguments   => nil
        }.merge(h)
      else
        h
      end
    end
  end
end
