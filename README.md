# WebsocketSequentialClient

This ruby gem library allows you to access a WebSocket server in a **sequential** way instead of an event-driven way.

## Features

### Provides access to a WebSocket server in a *sequential* way.  

Many gem libraries for WebSocket client use *event-driven* style.  
This style has many advantages, but it's not so easy to understand.  
This gem library provides a *simple* and *sequential* access to a WebSocket server.

### Independent from eventmachine and other frameworks.  

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

## Versions

* 1.0.0  
  Initial release

