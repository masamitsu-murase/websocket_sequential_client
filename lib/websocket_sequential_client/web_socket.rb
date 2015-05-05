require("websocket")
require("uri")
require("socket")
require("thread")

module WebsocketSequentialClient
  class WebSocket
    DEFAULT_PING_INTERVAL = 20
    DEFAULT_CLOSE_CODE = 1000
    DEFAULT_CLOSE_TIMEOUT = 20

    RECV_SIZE = 1024

    WS_PORT = 80

    def self.open *args, &block
      if block
        ws = self.new *args
        begin
          block.call ws
        ensure
          ws.close
        end
      else
        self.new *args
      end
    end

    def initialize url, opt = { ping: true, headers: {} }
      @read_queue = ReadQueue.new
      @write_queue = WriteQueue.new

      @closed_status_mutex = Mutex.new
      @closed_status_cond_var = ConditionVariable.new
      @closed_status = nil
      @close_timeout = DEFAULT_CLOSE_TIMEOUT

      @close_code = nil
      @close_reason = nil

      @ping_th = nil

      url = URI.parse url.to_s unless url.kind_of? URI
      @url = url

      case url.scheme
      when "ws"
        @socket = TCPSocket.new(url.host, url.port || WS_PORT)
      else
        raise ArgumentError, "URL scheme must be 'ws'."
      end

      hs = handshake(opt[:headers])

      @version = hs.version

      Thread.start{ send_background }
      Thread.start{ receive_background }
      start_ping_thread opt[:ping] if opt[:ping]

    rescue
      close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
      raise
    end
    attr_reader :close_code, :close_reason

    def available?
      @read_queue.available?
    end
    alias data_available? available?

    def recv
      data = @read_queue.pop
      raise data if data.kind_of? StandardError

      case data.type
      when :text
        data.to_s.force_encoding Encoding::UTF_8
      when :binary
        data.to_s.force_encoding Encoding::BINARY
      else
        raise NotImplementedError
      end
    end
    alias receive recv

    def send data, type = :guess
      case type
      when :guess
        if data.encoding == Encoding::BINARY
          type = :binary
        elsif Encoding.compatible?(data.encoding, Encoding::UTF_8)
          type = :text
        else
          raise ArgumentError, "Invalid encoding."
        end
      when :text
        unless Encoding.compatible?(data.encoding, Encoding::UTF_8)
          raise ArgumentError, "Invalid encoding"
        end
      when :binary
        #
      else
        raise ArgumentError, "Invalid type specified"
      end

      # data.b is necessary for the current implementation of websocket gem library.
      frame = ::WebSocket::Frame::Outgoing::Client.new(data: data.b, type: type, version: @version)

      result = @write_queue.process_frame frame
      raise result if result.kind_of? StandardError
    end

    def send_text data
      send data, :text
    end

    def send_binary data
      send data, :binary
    end

    def close code = nil, reason = nil, opt = { timeout: DEFAULT_CLOSE_TIMEOUT, wait_for_response: true }
      code ||= DEFAULT_CLOSE_CODE
      param = {
        code: code,
        type: :close,
        version: @version
      }
      param[:data] = reason if reason
      frame = ::WebSocket::Frame::Outgoing::Client.new(param)

      @close_timeout = (opt.key?(:timeout) ? opt[:timeout] : DEFAULT_CLOSE_CODE)
      @write_queue.process_frame frame

      wait_for_response = (opt.key?(:wait_for_response) ? opt[:wait_for_response] : true)
      if wait_for_response
        @closed_status_mutex.synchronize do
          @closed_status_cond_var.wait @closed_status_mutex until @closed_status == :closed
        end
      end
    end

    private
    def handshake headers
      hs = ::WebSocket::Handshake::Client.new(url: @url.to_s, headers: headers)

      @socket.send(hs.to_s, 0)

      begin
        data = @socket.recv(1)
        raise HandshakeFailed if data.empty?
        hs << data
      end until hs.finished?

      raise HandshakeFailed unless hs.valid?

      hs
    end

    def start_ping_thread ping_opt
      interval = (ping_opt[:interval] rescue DEFAULT_PING_INTERVAL)
      raise ArgumentError, "opt[:ping][:interval] must be a positive number." if interval <= 0
      @ping_th = Thread.start(interval) do |i|
        while true
          sleep i
          return if @closed_status

          frame = ::WebSocket::Frame::Outgoing::Client.new(type: :ping, version: @version)
          @write_queue.push frame
        end
      end
    end

    def kill_ping_thread
      return unless @ping_th

      @ping_th.kill rescue nil
      @ping_th = nil
    end

    def receive_next_data
      data = @socket.recv(RECV_SIZE)
      if data.empty?
        # Unexpected close
        close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
        return nil
      end
      return data
    rescue => e
      @read_queue.push e
      close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
      return nil
    end

    def receive_background
      input = ::WebSocket::Frame::Incoming::Client.new

      data = receive_next_data
      return unless data

      input << data

      while true
        error = false
        begin
          next_frame = input.next
          error = true if input.error
        rescue
          error = true
        end
        if error
          @read_queue.push InvalidDataReceived.new
          close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
          return
        end

        unless next_frame
          data = receive_next_data
          return unless data

          input << data
          next
        end

        case next_frame.type
        when :text, :binary
          @read_queue.push next_frame

        when :close
          @read_queue.close SocketAlreadyClosed.new
          @close_code = next_frame.code
          @close_reason = (next_frame.data && next_frame.data.to_s.force_encoding(Encoding::UTF_8))

          @closed_status_mutex.synchronize do
            unless @closed_status
              @closed_status = :close_frame_received
              @closed_status_cond_var.broadcast
            end
          end

          # After close_frame_received is set to true, all frames are ignored.
          kill_ping_thread

          # If @write_queue is already closed, frame will be ignored.
          frame = ::WebSocket::Frame::Outgoing::Client.new(code: next_frame.code,
                                                       type: :close, version: @version)
          @write_queue.push frame  # Ignore result.

          return

        when :ping
          f = ::WebSocket::Frame::Outgoing::Client.new(data: next_frame.to_s,
                                                   type: :pong, version: @version)
          @write_queue.push f

        when :pong
          # Ignore

        else
          # Unknown packet.
          @read_queue.push InvalidDataReceived.new
          close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
          return

        end
      end
    rescue SignalException, StandardError
      critical_close
    end

    def send_background
      while true
        frame = @write_queue.pop

        begin
          @socket.send(frame.to_s, 0)
        rescue => e
          @write_queue.push_result frame, e
          close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
          return
        end

        case frame.type
        when :text, :binary
          @write_queue.push_result frame, true
        when :close
          @write_queue.push_result frame, true
          close_process
          return
        else
          # ping and pong are ignored.
        end
      end
    rescue SignalException, StandardError
      critical_close
    end

    def critical_close
      begin
        close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
      rescue
      end
    end

    def close_process
      kill_ping_thread

      # Always start with shutdown of write.
      @socket.shutdown Socket::SHUT_WR rescue nil
      @write_queue.close SocketAlreadyClosed.new
      # Then, try to receive a close frame from the server.
      @closed_status_mutex.synchronize do
        unless @closed_status
          @closed_status_cond_var.wait(@closed_status_mutex, @close_timeout)
        end
      end

      case @closed_status
      when nil
        # An error occurs and a close frame is not sent from the server,
        # so close anyway.
        @socket.shutdown Socket::SHUT_RD
        close_socket(SocketAlreadyClosed.new, SocketAlreadyClosed.new)
      when :close_frame_received
        begin
          true until @socket.recv(RECV_SIZE).empty?
          @socket.shutdown Socket::SHUT_RD
        rescue
        end
        close_socket(nil, nil)
      when :closed
        # Nothing to do.
      end
    end

    def close_socket(wr_queue_error, rd_queue_error)
      @write_queue.close wr_queue_error if wr_queue_error
      @read_queue.close rd_queue_error if rd_queue_error

      @socket.close rescue nil
      @closed_status_mutex.synchronize do
        @closed_status = :closed
        @closed_status_cond_var.broadcast
      end

      kill_ping_thread  # Fail safe
    end
  end
end
