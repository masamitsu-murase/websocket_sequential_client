# -*- coding: utf-8 -*-

require 'spec_helper'

describe WebsocketSequentialClient do
  URL = test_url

  after :each do
    stop_ws_server
    stop_tcp_server
  end

  def start_ws_server(&block)
    mutex = Mutex.new
    cond_var = ConditionVariable.new
    started = false

    @ws_thread = Thread.start do
      EM.run do
        param = {
          host: URL.host,
          port: URL.port
        }
        EM::WebSocket.start(param) do |ws|
          ws.onmessage do |msg|
            block.call ws, :onmessage, msg
          end

          ws.onbinary do |msg|
            block.call ws, :onbinary, msg
          end

          ws.onclose do |msg|
            block.call ws, :onclose, msg
          end

          ws.onping do
            block.call ws, :onping
          end
        end

        mutex.synchronize do
          started = true
          cond_var.signal
        end
      end
    end

    mutex.synchronize do
      cond_var.wait mutex until started
    end
  end

  def stop_ws_server
    return unless @ws_thread

    EM.stop
    @ws_thread.join
    @ws_thread = nil
  end

  def start_tcp_server(&block)
    @server = TCPServer.new(URL.host, URL.port)
    @tcp_thread = Thread.start(@server) do |server|
      s = server.accept
      begin
        block.call s
      ensure
        s.close unless s.closed?
      end
    end
  end

  def stop_tcp_server
    if @server
      @server.close
      @server = nil
    end

    if @tcp_thread
      @tcp_thread.join
      @tcp_thread = nil
    end
  end


  #================================================================
  it 'can access WebSocket server' do
    sent_message_list = [ "a", "", "日本語", "long" * 64 * 1024, "end" ]
    received_message_list = []
    sent_back_message_list = []
    received_prefix = "rcv: "

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        received_message_list.push msg
        ws.send "#{received_prefix}#{msg}"
        ws.close if msg == "end"
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    sent_message_list.each do |msg|
      ws.send msg, :text
      sent_back_message_list.push ws.receive
    end

    expect{ stop_ws_server }.to_not raise_error
    expect(received_message_list).to eq sent_message_list
    expect(sent_back_message_list).to eq sent_message_list.map{ |i| "#{received_prefix}#{i}" }
  end

  #----------------------------------------------------------------
  it 'can receive long message' do
    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        ws.send msg*64*1024
      when :onbinary
        ws.send msg*64*2048
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.send "long"
    expect(ws.recv).to eq "long" * 64 * 1024
    ws.send "long".b
    expect(ws.recv).to eq "long".b * 64 * 2048
    ws.close
  end

  #----------------------------------------------------------------
  it 'can access WebSocket server in block style' do
    closed_on_server = false
    start_ws_server do |ws, type, msg=nil|
      case type
      when :onclose
        closed_on_server = true
      end
    end

    WebsocketSequentialClient::WebSocket.open URL.to_s do |ws|
      ws.send "message"
    end
    expect(closed_on_server).to eq true

    closed_on_server = false
    WebsocketSequentialClient::WebSocket.open URL.to_s do |ws|
      ws.send "message"
      ws.close
    end
    expect(closed_on_server).to eq true
  end

  #----------------------------------------------------------------
  it 'can close WebSocket connection' do
    sent_message = "message"
    received_message = nil
    closed_on_server = false

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        received_message = msg
      when :onclose
        closed_on_server = true
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.send sent_message
    ws.close

    expect(received_message).to eq sent_message
    expect(closed_on_server).to eq true
  end

  #----------------------------------------------------------------
  it 'can skip server response when connection' do
    closed_on_server = false
    mutex = Mutex.new
    cond_var = ConditionVariable.new
    stop = true

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        received_message = msg
      when :onclose
        mutex.synchronize do
          cond_var.wait mutex while stop
        end
        closed_on_server = true
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.send "message"
    ws.close nil, nil, wait_for_response: false

    expect(closed_on_server).to eq false

    mutex.synchronize do
      stop = false
      cond_var.signal
    end
  end

  #----------------------------------------------------------------
  it 'can specify close code' do
    close_code = nil

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onclose
        close_code = msg[:code]
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.close 4000

    expect(close_code).to eq 4000
    expect(ws.close_code).to eq 4000  # Server should return same code.
  end

  it 'can specify close reason' do
    close_reason = nil

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onclose
        close_reason = msg[:reason]
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.close nil, "close reason"

    expect(close_reason).to eq "close reason"
  end

  it 'can get close code and reason' do
    close_reason = nil

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        ws.close 4001, "closed by server"
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    ws.send "please close"
    expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
    expect(ws.close_code).to eq 4001
    expect(ws.close_reason).to eq "closed by server"
  end

  #----------------------------------------------------------------
  it 'can check data availability' do
    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        ws.send "response"
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    expect(ws.available?).to eq false
    ws.send "message"
    expect{ timeout(1){ sleep 0.1 until ws.available? } }.to_not raise_error
    expect(ws.recv).to eq "response"
  end

  #----------------------------------------------------------------
  it 'can ping to server' do
    sent_message = "message"
    received_message = nil
    ping_count = 0

    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        received_message = msg
      when :onping
        ping_count += 1
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL, ping: { interval: 0.1 }
    sleep 1
    ping_count1 = ping_count
    ws.send sent_message
    sleep 1
    ping_count2 = ping_count - ping_count1
    ws.close

    expect(received_message).to eq sent_message
    expect(ping_count1).to be >= 8
    expect(ping_count2).to be >= 8
  end

  #----------------------------------------------------------------
  it 'can send text and binary messages' do
    received_messages = []
    received_text_messages = []
    received_binary_messages = []
    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        if msg == "close"
          ws.close
          next
        end
        received_messages.push msg
        received_text_messages.push msg
      when :onbinary
        received_messages.push msg
        received_binary_messages.push msg
      end
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    text_messages = [ "", "abc", "日本語" ]
    binary_messages = [ "".b, [ 0, 1, 2, 3 ].pack("C*") ]
    messages = text_messages + binary_messages
    messages.each do |msg|
      ws.send msg
    end
    ws.send "close"
    ws.close

    expect(received_text_messages).to eq text_messages
    expect(received_binary_messages).to eq binary_messages
    expect(received_binary_messages.all?{ |i| i.encoding == Encoding::BINARY }).to be true
    expect(received_messages).to eq messages
  end

  #----------------------------------------------------------------
  it "can receive separated frame." do
    start_tcp_server do |s|
      hs = ::WebSocket::Handshake::Server.new
      begin
        data = s.recv(1)
        hs << data
      end until hs.finished?
      s.send hs.to_s.b, 0

      frame = ::WebSocket::Frame::Outgoing::Server.new(data: "abc"*100, type: :text, version: hs.version)
      data = frame.to_s.b
      s.send data.slice(0 ... data.size/2), 0
      s.flush
      Thread.pass
      s.send data.slice(data.size/2 .. -1), 0
    end

    ws = WebsocketSequentialClient::WebSocket.new URL
    expect(ws.recv).to eq "abc" * 100
  end

  #----------------------------------------------------------------
  it "can send extra headers." do
    headers = { "WSTEST-HEADER1" => "Value1", "WSTEST-HEADER2" => "Value2" }
    hs_headers = nil
    start_tcp_server do |s|
      hs = ::WebSocket::Handshake::Server.new
      begin
        data = s.recv(1)
        hs << data
      end until hs.finished?
      hs_headers = hs.headers
      s.send hs.to_s.b, 0

      frame = ::WebSocket::Frame::Outgoing::Server.new(data: "abc", type: :text, version: hs.version)
      data = frame.to_s.b
      s.send data, 0
    end

    ws = WebsocketSequentialClient::WebSocket.new URL, headers: headers
    expect(ws.recv).to eq "abc"
    expect(hs_headers["wstest-header1"]).to eq "Value1"
    expect(hs_headers["wstest-header2"]).to eq "Value2"
  end

  #----------------------------------------------------------------
  it 'can run long time and simultaneously'do
    start_ws_server do |ws, type, msg=nil|
      case type
      when :onmessage
        ws.send msg
      end
    end

    threads = []
    error = false
    20.times do
      th = Thread.start do
        ws = WebsocketSequentialClient::WebSocket.new URL, ping: { interval: 0.1 }
        500.times do |i|
          2.times do |j|
            ws.send "count: #{i}:#{j}"
          end
          2.times do |j|
            if ws.receive != "count: #{i}:#{j}"
              error = true
            end
          end
        end
        ws.close
      end
      threads.push th
    end

    threads.each(&:join)

    expect(error).to be false
  end

  #================================================================
  describe "connect via SSL. (not supported yet)" do
    xit "can access server via SSL." do
      expect(false).to be true
    end
  end

  #================================================================
  describe "check send/recv after close" do
    it 'cannot send data after closed.' do
      start_ws_server do |ws, type, msg=nil|
        case type
        when :onmessage
          ws.close
        end
      end

      ws = WebsocketSequentialClient::WebSocket.new URL
      ws.send "end"
      sleep 0.5
      expect{ ws.send "invalid" }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed

      ws = WebsocketSequentialClient::WebSocket.new URL
      ws.send_binary "end"
      ws.close
      expect{ ws.send "invalid" }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
    end

    it 'cannot receive data after closed.' do
      start_ws_server do |ws, type, msg=nil|
        case type
        when :onmessage
          ws.close
        end
      end

      ws = WebsocketSequentialClient::WebSocket.new URL
      ws.send "end"
      sleep 0.5
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed

      ws = WebsocketSequentialClient::WebSocket.new URL
      ws.send_binary "end"
      ws.close
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
    end
  end

  describe "handshake error" do
    it 'can raise handshake error when invalid handshake text is returned.' do
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        response = hs.to_s.b
        # Make invalid response
        response[-10] = (response[-10].ord.succ % 256).chr
        s.send response, 0
        s.recv 10 rescue nil
      end

      expect{ WebsocketSequentialClient::WebSocket.new URL }.to raise_error WebsocketSequentialClient::HandshakeFailed
    end

    it 'can raise handshake error if connection is closed.' do
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        response = hs.to_s.b
        s.send response.slice(0 .. response.size/2), 0
        s.close
      end

      expect{ WebsocketSequentialClient::WebSocket.new URL }.to raise_error WebsocketSequentialClient::HandshakeFailed
    end
  end

  describe "sent/recv data error" do
    it "can raise error when invalid data is sent from server" do
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        s.send hs.to_s.b, 0

        frame = ::WebSocket::Frame::Outgoing::Server.new(data: "abc", type: :text, version: hs.version)
        data = frame.to_s.b
        # Make invalid data
        data[0] = 0x83.chr
        s.send data, 0
        s.recv 10 rescue nil
      end

      ws = WebsocketSequentialClient::WebSocket.new URL
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::InvalidDataReceived
      expect{ ws.send "a" }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
    end

    it "can raise error when connection is closed" do
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        s.send hs.to_s.b, 0

        frame = ::WebSocket::Frame::Outgoing::Server.new(data: "abc", type: :text, version: hs.version)
        data = frame.to_s.b
        s.send data.slice(0 .. data.size/2), 0
      end

      ws = WebsocketSequentialClient::WebSocket.new URL
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
      expect{ ws.send "a" }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
      expect{ ws.recv }.to raise_error WebsocketSequentialClient::SocketAlreadyClosed
    end
  end

  describe "close error" do
    it "does not hang when no close frame is sent." do
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        s.send hs.to_s.b, 0

        s.recv 4096  # Receives close frame
        # Then, does not send close frame.
      end

      ws = WebsocketSequentialClient::WebSocket.new URL
      expect{ Timeout.timeout(1){ ws.close } }.to_not raise_error
    end

    it "can return from close method after timeout when no close frame is sent for a while." do
      mutex = Mutex.new
      cond_var = ConditionVariable.new
      hang_server = true
      start_tcp_server do |s|
        hs = ::WebSocket::Handshake::Server.new
        begin
          data = s.recv(1)
          hs << data
        end until hs.finished?
        s.send hs.to_s.b, 0

        s.recv 4096  # Receives close frame
        # Then, wait forever
        mutex.synchronize do
          cond_var.wait mutex while hang_server
        end
      end

      begin
        ws = WebsocketSequentialClient::WebSocket.new URL
        expect{ timeout(1){ ws.close(nil, nil, timeout: 0.5) } }.to_not raise_error
      ensure
        mutex.synchronize do
          hang_server = false
          cond_var.signal
        end
      end
    end
  end
end
