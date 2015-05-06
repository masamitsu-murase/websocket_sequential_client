# -*- coding: utf-8 -*-

module WebsocketSequentialClient
  #
  # Base errror class
  #
  class Error < StandardError
  end

  #
  # This error is raised when <tt>recv</tt> or <tt>send</tt> is called after the socket is closed.
  #
  class SocketAlreadyClosed < Error
  end

  #
  # This error is raised when handshake with a server failed.
  #
  class HandshakeFailed < Error
  end

  #
  # This error is raised when a invaid data is received.
  #
  class InvalidDataReceived < Error
  end
end
