$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'websocket_sequential_client'
require("em-websocket")
require("websocket")
require("timeout")
require("socket")
require("uri")

def port_used? port
  s = TCPSocket.new "localhost", port
  s.close
  true
rescue Errno::ECONNREFUSED
  false
end

def test_url
  port = 8000
  while port_used?(port) && port < 10000
    port += 1
  end

  URI.parse("ws://localhost:#{port}")
end

