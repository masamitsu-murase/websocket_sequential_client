# WebsocketSequentialClient [![Build Status](https://travis-ci.org/masamitsu-murase/websocket_sequential_client.svg)](https://travis-ci.org/masamitsu-murase/websocket_sequential_client)

This ruby gem library allows you to access a WebSocket server in a **sequential** way instead of an event-driven way.

## Features

* Provides access to a WebSocket server in a *sequential* way.  
  Many gem libraries for WebSocket client use *event-driven* style.  
  This style has many advantages, but it's not so easy to understand.  
  This gem library provides a *simple* and *sequential* access to a WebSocket server.

* Independent from eventmachine and other frameworks.  
  You can use this gem library with/without eventmachine and other frameworks.  
  Eventmachine is a great and useful library, but it uses some global functions, such as `EM.run`, `EM.stop` and so on, so it might conflicts with *your* environment.  
  This gem library does not depends on any frameworks, so you can use it in your environment.

If you need performance and/or scalability, you should use the other great libraries, such as em-websocket.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'websocket_sequential_client'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install websocket_sequential_client

## Usage

Call `send` and `recv` to communicate with the server.

```ruby
require "websocket_sequential_client"

WebSocketSequentialClient::WebSocket.open "ws://server-url" do |ws|
  ws.send "Hello"
  puts ws.recv
end
```

**Note**: `recv` method is a *blocking* method. It will wait until a message is sent from the server.

## More examples

### Send and receive *text* and *binary* messages.

```ruby
# coding: utf-8

require "websocket_sequential_client"

ws = WebSocketSequentialClient::WebSocket.new "ws://server-url"

# `send` method guesses whether the argument is text or binary based on the encoding.
# The encoding of "Hello" is UTF-8, so the messages is sent as text.
ws.send "Hello"

# You can also use `send_text` method.
ws.send_text "World"


# The following lines send binary messages
# because the argument has ASCII-8BIT encoding.
ws.send [0,1,2,3].pack("C*")
ws.send "example".b

# Of course, `send_binary` is supported.
ws.send_binary "binary message"


# You can receive messages from the server with `recv`.
# If the server sent "text" message, msg has UTF-8 encoding.
# In the case of "binary" message, msg has ASCII-8BIT encoding.
msg = ws.recv

ws.close
```

### Ping and pong.

`ping` and `pong` frames are sent in background, so you need not to handle these frames.

```ruby
require "websocket_sequential_client"

# `ping` is enabled as default. The interval is 20s.
ws = WebSocketSequentialClient::WebSocket.new "ws://server-url"
#...
ws.close

# You can disable `ping`.
ws = WebSocketSequentialClient::WebSocket.new "ws://server-url", ping: false
#...
ws.close

# You can change the interval of `ping` to 10s.
ws = WebSocketSequentialClient::WebSocket.new "ws://server-url", ping: { interval: 10 }
#...
ws.close
```

### Send additional headers.

You can send additional headers with the request of HTTP handshake.

```ruby
require "websocket_sequential_client"

# Add "Cookie" field to the HTTP request.
ws = WebSocketSequentialClient::WebSocket.new "ws://server-url", headers: { "Cookie" => "value1" }
#...
ws.close
```


## Versions

* 1.0.0  
  Initial release

